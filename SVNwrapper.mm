#include "SVNProgress.h"
#include "SVNAuthorise.h"

apr_pool_t *APR::pool;

void APR::Init() {
	if (!pool) {
		apr_status_t	apr;
		apr	= apr_initialize();
		apr	= apr_pool_create(&pool, NULL);
	}
}


@implementation NSString (Paths)

-(NSString*)relativeTo:(NSString*)base {
	NSArray	*fn_comps	= [self pathComponents];
	NSArray	*base_comps	= [base pathComponents];
	int		base_n		= [base_comps count];
	int		fn_n		= [fn_comps count];

	int		i = 0;
	while (i < base_n && i < fn_n && [[fn_comps objectAtIndex:i] isEqualToString:[base_comps objectAtIndex:i]])
		i++;
		
	NSString	*result = [[NSString new] autorelease];
	while (i < base_n--)
		result = [result stringByAppendingPathComponent:@".."];

	while (i < fn_n)
		result = [result stringByAppendingPathComponent:[fn_comps objectAtIndex:i++]];
		
	return result;
}

-(NSString*)getUTI {
	return [(NSString*)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)[self pathExtension], NULL) autorelease];
}

-(NSString*)getUTIDescription {
	NSString	*ext	= [self pathExtension];
    CFStringRef uti		= UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (CFStringRef)ext, NULL);
    CFStringRef	desc	= UTTypeCopyDescription(uti);
    CFRelease(uti);
	return desc ? [(NSString*)desc autorelease] : ext;
}

-(bool)isDir {
	BOOL	dir;
	return [[NSFileManager defaultManager] fileExistsAtPath:self isDirectory:&dir] && dir;
}

@end

@implementation NSString (SVN)
+(NSString*)stringWithSVNString:(const svn_string_t*)svn_string {
	return svn_string
		? [NSString stringWithUTF8String:svn_string->data]
		: @"";
}
-(svn_string_t*)SVNStringWithPool:(apr_pool_t*)pool {
	return svn_string_create([self UTF8String], pool);
}
-(const char*)APRStringWithPool:(apr_pool_t*)pool {
	return apr_pstrdup(pool, [self UTF8String]);
}
@end

@implementation NSData (SVN)
-(svn_string_t*)SVNStringWithPool:(apr_pool_t*)pool {
	return svn_string_ncreate((const char*)[self bytes], [self length], pool);
}
@end

//------------------------------------------------------------------------------
//	SVNClientStatus
//------------------------------------------------------------------------------

@implementation SVNClientStatus

+(SVNClientStatus*)createWithCType: (const svn_client_status_t*)status {
	return [[[SVNClientStatus alloc] initWithCType: status] autorelease];
}

-(SVNClientStatus*)initWithCType: (const svn_client_status_t*)status {
	if (self = [super init]) {
		path		= status->local_abspath	? [[NSString stringWithUTF8String:status->local_abspath]	retain] : nil;
		changelist	= status->changelist	? [[NSString stringWithUTF8String:status->changelist]		retain] : nil;
		filesize	= status->filesize;
		conflicted	= status->conflicted;
		base_rev	= status->revision;
		
		local.init(status->kind, status->node_status, status->text_status, status->prop_status,
			status->lock, status->changed_rev, status->changed_date
		);
		repos.init(status->ood_kind, status->repos_node_status, status->repos_text_status, status->repos_prop_status,
			status->repos_lock, status->ood_changed_rev, status->ood_changed_date
		);
	}
	return self;
}

-(void)dealloc {
	if (path)
		[path release];
	if (changelist)
		[changelist release];
	local.dealloc();
	repos.dealloc();
	[super dealloc];
}

NSString *svn_status[] = {
	@"",
	@"none",
	@"unversioned",
	@"normal",
	@"added",
	@"missing",
	@"deleted",
	@"replaced",
	@"modified",
	@"merged",
	@"conflicted",
	@"ignored",
	@"obstructed",
	@"external",
	@"incomplete"
};

-(NSString*)path		{ return path; }
-(NSString*)lock		{ return local.lock_owner; }
-(NSString*)text_status	{ return svn_status[local.node_status]; }
-(NSString*)prop_status	{ return svn_status[local.prop_status]; }

@end
//------------------------------------------------------------------------------
//	SVNClientInfo
//------------------------------------------------------------------------------

@implementation SVNClientInfo

-(SVNClientInfo*)initWithCType:(const svn_client_info2_t*)info {
	if (self = [super init]) {
		URL					= [[NSString stringWithUTF8String:info->URL] retain];
		repos_root_URL		= [[NSString stringWithUTF8String:info->repos_root_URL] retain];
		repos_UUID			= [[NSString stringWithUTF8String:info->repos_UUID] retain];
		if (last_changed_author)
			last_changed_author	= [[NSString stringWithUTF8String:info->last_changed_author] retain];

		rev					= info->rev;
		kind				= info->kind;
		size				= info->size;
		last_changed_rev	= info->last_changed_rev;
		last_changed_date	= info->last_changed_date;
	}
	return self;
}

-(void)dealloc {
	[URL					release];
	[repos_root_URL			release];
	[repos_UUID				release];
	[last_changed_author	release];
	[super dealloc];
}

+(SVNClientInfo*)createWithCType: (const svn_client_info2_t*)info {
	return [[[SVNClientInfo alloc] initWithCType:info] autorelease];
}
@end

//------------------------------------------------------------------------------
//	svn_diff_diff_1
//------------------------------------------------------------------------------

svn_error_t *svn_diff_diff_1(svn_diff_t **diff, void *diff_baton, const svn_diff_fns2_t *diff_fns, apr_pool_t *pool) {
	svn_diff_datasource_e	datasource = svn_diff_datasource_original;
	apr_off_t	prefix_lines	= 0;
	apr_off_t	suffix_lines	= 0;

	if 	(svn_error_t *err = diff_fns->datasources_open(diff_baton, &prefix_lines, &suffix_lines, &datasource, 1))
		return err;
		
	for (;;) {
		apr_uint32_t	hash;
		void			*token	= 0;
		if (svn_error_t *err = diff_fns->datasource_get_next_token(&hash, &token, diff_baton, datasource))
			return err;
		if (!token)
			break;
	}
	
	return diff_fns->datasource_close(diff_baton, datasource);
}

//------------------------------------------------------------------------------
//	PromptDelegate
//------------------------------------------------------------------------------

@interface PromptDelegate : NSObject {
	NSConditionLock	*lock;
	NSInteger		returnCode;
}
@end

@implementation PromptDelegate

-(id)init {
	if (self = [super init]) {
		lock	= [[NSConditionLock alloc] initWithCondition:0];
	}
	return self;
}
-(void)dealloc {
	[lock unlock];
	[lock release];
	[super dealloc];
}

-(void)start {
	[lock lock];
}
-(void)stopWith:(NSInteger)value {
	returnCode	= value;
	[lock unlockWithCondition:1];
}
-(void)alertDidEnd:(NSAlert*)alert returnCode:(NSInteger)value contextInfo:(void*)p {
	returnCode	= value;
	[lock unlockWithCondition:1];
}
-(NSInteger)result {
	[lock lockWhenCondition:1];
	return returnCode;
}

@end

svn_error_t *
svn_config_get_config(apr_hash_t **cfg_hash,
                      const char *config_dir,
                      apr_pool_t *pool);
//------------------------------------------------------------------------------
//	SVNcontext
//------------------------------------------------------------------------------

svn_error_t	*SVNcontext::simple_prompt(svn_auth_cred_simple_t **cred, const char *realm, const char *username, svn_boolean_t may_save, apr_pool_t *pool) {
	SVNAuthorise	*auth = [SVNAuthorise new];
	
	dispatch_async(dispatch_get_main_queue(), ^ {
		[auth runWithRealm:[NSString stringWithUTF8String:realm] username:username ? [NSString stringWithUTF8String:username] : nil];
	});

	[auth waitUntilDone];
	
	if (auth->ok) {
		svn_auth_cred_simple_t *ret = new(pool) svn_auth_cred_simple_t;
		ret->username = [auth->username APRStringWithPool:pool];
		ret->password = [auth->password APRStringWithPool:pool];
		ret->may_save = may_save;
		*cred = ret;
	} else {
		*cred = NULL;
	}
	
	[auth release];
	return SVN_NO_ERROR;
}

svn_error_t	*SVNcontext::username_prompt(svn_auth_cred_username_t **cred, const char *realm, svn_boolean_t may_save, apr_pool_t *pool) {
	SVNAuthorise	*auth = [SVNAuthorise new];
	
	dispatch_async(dispatch_get_main_queue(), ^ {
		[auth runWithRealm:[NSString stringWithUTF8String:realm] username:nil];
	});

	[auth waitUntilDone];
	
	if (auth->ok) {
		svn_auth_cred_username_t *ret = new(pool) svn_auth_cred_username_t;
		ret->username = [auth->username APRStringWithPool:pool];
		ret->may_save = may_save;
		*cred = ret;
	} else {
		*cred = NULL;
	}
	
	[auth release];
	return SVN_NO_ERROR;
}

svn_error_t	*SVNcontext::ssl_server_trust_prompt(svn_auth_cred_ssl_server_trust_t **cred, const char *realm, apr_uint32_t failures,const svn_auth_ssl_server_cert_info_t *cert_info,svn_boolean_t may_save,apr_pool_t *pool) {

	NSString	*reason	= @"";
	
	if (failures & SVN_AUTH_SSL_UNKNOWNCA)
		reason = [reason stringByAppendingString:@" - The certificate is not issued by a trusted authority. Use the fingerprint to validate the certificate manually!\n"];

	if (failures & SVN_AUTH_SSL_CNMISMATCH)
		reason = [reason stringByAppendingString:@" - The certificate hostname does not match.\n"];

	if (failures & SVN_AUTH_SSL_NOTYETVALID)
		reason = [reason stringByAppendingString:@" - The certificate is not yet valid.\n"];

	if (failures & SVN_AUTH_SSL_EXPIRED)
		reason = [reason stringByAppendingString:@" - The certificate has expired.\n"];

	if (failures & SVN_AUTH_SSL_OTHER)
		reason = [reason stringByAppendingString:@" - The certificate has an unknown error.\n"];

	NSAlert		*alert		= [NSAlert alertWithMessageText:@"Subversion"
		defaultButton:@"Reject"
		alternateButton:@"Accept Temporarily"
		otherButton:(may_save ? @"Accept Permanently" : nil)
		informativeTextWithFormat:@
			"Error validating server certificate for '%s':\n"
			"%@"
			"Certificate information:\n"
			" - Hostname: %s\n"
			" - Valid: from %s until %s\n"
			" - Issuer: %s\n"
			" - Fingerprint: %s\n",
			realm,
			reason,
			cert_info->hostname,
			cert_info->valid_from,
			cert_info->valid_until,
			cert_info->issuer_dname,
			cert_info->fingerprint
	];
	
	PromptDelegate	*prompt = [[PromptDelegate new] autorelease];
	dispatch_async(dispatch_get_main_queue(), ^ {
		[prompt start];
		[alert beginSheetModalForWindow: window modalDelegate:prompt didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
	});

	switch ([prompt result]) {
		case NSAlertDefaultReturn:
			*cred = NULL;
			break;
		case NSAlertAlternateReturn:
			*cred = new(pool) svn_auth_cred_ssl_server_trust_t;
			(*cred)->may_save			= FALSE;
			(*cred)->accepted_failures	= failures;
			break;
		case NSAlertOtherReturn:
			*cred = new(pool) svn_auth_cred_ssl_server_trust_t;
			(*cred)->may_save			= TRUE;
			(*cred)->accepted_failures	= failures;
			break;
	}

	return SVN_NO_ERROR;
}

svn_error_t	*SVNcontext::ssl_client_cert_prompt(svn_auth_cred_ssl_client_cert_t **cred, const char *realm, svn_boolean_t may_save,apr_pool_t *pool) {

	NSOpenPanel *dlg	= [NSOpenPanel openPanel];
	[dlg setMessage:		[NSString stringWithFormat:@"Select certificate for %s", realm]];
	[dlg setPrompt:			@"Select certificate"];
//	[dlg setDirectoryURL:	[dirs objectAtIndex:0]];
	[dlg setAllowsMultipleSelection:NO];
	[dlg setCanChooseDirectories:	NO];

	PromptDelegate		*prompt = [[PromptDelegate new] autorelease];
	__block NSURL		*filename;
	dispatch_async(dispatch_get_main_queue(), ^ {
		[prompt start];
		[dlg beginSheetModalForWindow:window completionHandler: ^(NSInteger result) {
			filename = [[dlg URLs] objectAtIndex:0];
			[prompt stopWith:result];
		}];
	});

	[prompt result];
	*cred = new(pool) svn_auth_cred_ssl_client_cert_t;
	(*cred)->cert_file	= [[filename path] SVNStringWithPool:pool]->data;
	(*cred)->may_save	= may_save;

	return SVN_NO_ERROR;
}

svn_error_t	*SVNcontext::ssl_client_cert_pw_prompt(svn_auth_cred_ssl_client_cert_pw_t **cred, const char *realm, svn_boolean_t may_save,apr_pool_t *pool) {
	SVNAuthorise	*auth = [SVNAuthorise new];
	
	dispatch_async(dispatch_get_main_queue(), ^ {
		[auth runWithRealm:[NSString stringWithUTF8String:realm] username:nil];
	});

	[auth waitUntilDone];
	
	if (auth->ok) {
		svn_auth_cred_ssl_client_cert_pw_t *ret = new(pool) svn_auth_cred_ssl_client_cert_pw_t;
		ret->password = [auth->password APRStringWithPool:pool];
		ret->may_save = may_save;
		*cred = ret;
	} else {
		*cred = NULL;
	}
	
	[auth release];
	return SVN_NO_ERROR;
}

svn_error_t	*SVNcontext::plaintext_prompt(svn_boolean_t *may_save_plaintext, const char *realm, apr_pool_t *pool) {
	const char *config_path;
	svn_config_get_user_config_path(&config_path, NULL, NULL, pool);

	NSAlert		*alert		= [NSAlert alertWithMessageText:@"Subversion"
		defaultButton:@"Yes"
		alternateButton:@"No"
		otherButton:nil
		informativeTextWithFormat:@
			"\nATTENTION!  Your password for authentication realm:\n"
			"\n"
			"   %s\n"
			"\n"
			"can only be stored to disk unencrypted!  You are advised to configure "
			"your system so that Subversion can store passwords encrypted, if "
			"possible.  See the documentation for details.\n\n"
			"You can avoid future appearances of this warning by setting the value "
			"of the 'store-plaintext-passwords' option to either 'yes' or 'no' in\n"
			"'%s'.\n"
			"Store password unencrypted?",
			realm,
			config_path
	];
	PromptDelegate	*prompt = [[PromptDelegate new] autorelease];
	dispatch_async(dispatch_get_main_queue(), ^ {
		[prompt start];
		[alert beginSheetModalForWindow: window modalDelegate:prompt didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
	});

	*may_save_plaintext = [prompt result] == NSAlertDefaultReturn;
	return SVN_NO_ERROR;
}
svn_error_t	*SVNcontext::plaintext_passphrase_prompt(svn_boolean_t *may_save_plaintext, const char *realm, apr_pool_t *pool) {
	const char *config_path;
	svn_config_get_user_config_path(&config_path, NULL, NULL, pool);
	
	NSAlert		*alert		= [NSAlert alertWithMessageText:@"Subversion"
		defaultButton:@"Yes"
		alternateButton:@"No"
		otherButton:nil
		informativeTextWithFormat:@
			"ATTENTION!  Your passphrase for client certificate:\n"
			"\n"
			"   %s\n"
			"\n"
			"can only be stored to disk unencrypted!  You are advised to configure "
			"your system so that Subversion can store passphrase encrypted, if "
			"possible.  See the documentation for details.\n\n"
			"You can avoid future appearances of this warning by setting the value "
			"of the 'store-ssl-client-cert-pp-plaintext' option to either 'yes' or "
			"'no' in '%s'.\n"
			"Store passphrase unencrypted?",
			realm,
			config_path
	];
	PromptDelegate	*prompt = [[PromptDelegate new] autorelease];
	dispatch_async(dispatch_get_main_queue(), ^ {
		[prompt start];
		[alert beginSheetModalForWindow: window modalDelegate:prompt didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:) contextInfo:nil];
	});
	*may_save_plaintext = [prompt result] == NSAlertDefaultReturn;
	return SVN_NO_ERROR;
}

SVNcontext::SVNcontext() {
	svn_error_t		*err;

	err	= svn_client_create_context(&ctx, pool);
	err = svn_config_get_config(&ctx->config, NULL, pool);
	
	APRarray<svn_auth_provider_object_t*>	providers(10);
	svn_auth_provider_object_t				*provider;
	
	if (ctx->config) {
		svn_config_t *cfg_config = APRhash(ctx->config).get(SVN_CONFIG_CATEGORY_CONFIG);
		if (cfg_config)
			err = svn_auth_get_platform_specific_client_providers(&providers, cfg_config, pool);
	}
	
//Tortoise
#if 1
//	svn_auth_get_tsvn_simple_provider(&provider, pool);
//	providers.push_back(provider);
	
	// The main disk-caching auth providers, for both 'username/password' creds and 'username' creds.
	svn_auth_get_simple_provider2(&provider, _cb_plaintext_prompt, this, pool);
	providers.push_back(provider);
	svn_auth_get_username_provider(&provider, pool);
	providers.push_back(provider);

	// The server-cert, client-cert, and client-cert-password providers.
	svn_auth_get_ssl_server_trust_file_provider(&provider, pool);
	providers.push_back(provider);
	svn_auth_get_ssl_client_cert_file_provider(&provider, pool);
	providers.push_back(provider);
	svn_auth_get_ssl_client_cert_pw_file_provider2(&provider, _cb_plaintext_passphrase_prompt, this, pool);
	providers.push_back(provider);

	// Two prompting providers, one for username/password, one for just username.
	svn_auth_get_simple_prompt_provider(&provider, _cb_simple_prompt, this, 3, pool);
	providers.push_back(provider);
	svn_auth_get_username_prompt_provider(&provider, _cb_username_prompt, this, 3, pool);
	providers.push_back(provider);

	// Three prompting providers for server-certs, client-certs, and client-cert-passphrases.
	svn_auth_get_ssl_server_trust_prompt_provider(&provider, _cb_ssl_server_trust_prompt, this, pool);
	providers.push_back(provider);
	svn_auth_get_ssl_client_cert_prompt_provider(&provider, _cb_ssl_client_cert_prompt, this, 2, pool);//tsvn
	providers.push_back(provider);
	svn_auth_get_ssl_client_cert_pw_prompt_provider(&provider, _cb_ssl_client_cert_pw_prompt, this, 2, pool);
	providers.push_back(provider);

//SCplugin:
#else
	svn_auth_get_keychain_simple_provider(&provider, pool);
	providers.push_back(provider);

	svn_auth_get_simple_provider2(&provider, _cb_plaintext_prompt, this, pool);
	providers.push_back(provider);

	svn_auth_get_username_provider(&provider, pool);
	providers.push_back(provider);

	svn_auth_get_ssl_server_trust_file_provider(&provider, pool);
	providers.push_back(provider);

	svn_auth_get_ssl_client_cert_file_provider(&provider, pool);
	providers.push_back(provider);

	svn_auth_get_ssl_client_cert_pw_file_provider2(&provider, _cb_plaintext_prompt, this, pool);
	providers.push_back(provider);
#endif

//common:
    svn_auth_baton_t	*auth;
	svn_auth_open(&auth, providers, pool);
	ctx->auth_baton		= auth;

	ctx->log_msg_func3	= __cb_log;
	ctx->log_msg_baton3	= 0;
}

SVNcontext::~SVNcontext() {
}

SVNcontext::SetDelegate::SetDelegate(SVNcontext *_svn, NSObject<SVNdelegate> *delegate, NSString *comment) : svn(_svn) {
	svn->window = [delegate window];
	
	svn_client_ctx_t	*ctx = svn->ctx;
	
	if ([delegate respondsToSelector:@selector(SVNnotify:pool:)]) {
		ctx->notify_func2	= _cb_notify;
		ctx->notify_baton2	= delegate;
	}
	
	if ([delegate respondsToSelector:@selector(SVNprogress:total:pool:)]) {
		ctx->progress_func	= _cb_progress;
		ctx->progress_baton = delegate;
	}
	
	if ([delegate respondsToSelector:@selector(SVNcancel)]) {
		ctx->cancel_func	= _cb_cancel;
		ctx->cancel_baton	= delegate;
	}
	
	ctx->log_msg_baton3	= comment;
}

SVNcontext::SetDelegate::~SetDelegate() {
	svn_client_ctx_t	*ctx = svn->ctx;
	ctx->notify_func2	= 0;
	ctx->progress_func	= 0;
	ctx->cancel_func	= 0;
	ctx->log_msg_baton3	= 0;
	svn->window			= nil;
}

NSString *SVNcontext::GetErrorMessage(const svn_error_t *err, bool all) {
	if (err) {
		char buffer[256];
		const char *mess = err->message ? err->message : svn_strerror(err->apr_err, buffer, sizeof(buffer));
		NSString *s = [NSString stringWithUTF8String:mess];
		if (all) {
			while ((err = err->child))
				s = [s stringByAppendingFormat:@"\n%s", err->message];
		}
		return s;
	}
	return nil;
}

void SVNcontext::LogErrorMessage(const svn_error_t *err) {
	if (err) {
		NSLog(@"%@", GetErrorMessage(err));
		while ((err = err->child))
			NSLog(@"%s", err->message);
	}
}
