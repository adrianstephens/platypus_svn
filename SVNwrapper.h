#ifndef SVNService_h
#define SVNService_h

#import <Cocoa/Cocoa.h>
//#import "Foundation/Foundation.h"
#define DARWIN
#import "svn_client.h"
#import "APRwrappers.h"

@interface NSString (Paths)
-(NSString*)relativeTo:(NSString*)base;
-(NSString*)getUTI;
-(NSString*)getUTIDescription;
-(bool)isDir;
@end

@interface NSString (SVN)
+(NSString*)stringWithSVNString:(const svn_string_t*)svn_string;
-(svn_string_t*)SVNStringWithPool:(apr_pool_t*)pool;
-(const char*)APRStringWithPool:(apr_pool_t*)pool;
@end

@interface NSData (SVN)
-(svn_string_t*)SVNStringWithPool:(apr_pool_t*)pool;
@end

//------------------------------------------------------------------------------
//	SVN wrappers
//------------------------------------------------------------------------------

struct SVNdate {
	apr_time_t	t;
	SVNdate(apr_time_t _t) : t(_t)		{}
	operator const apr_time_t() const	{ return t; }
	operator NSDate*()			const	{ return [NSDate dateWithTimeIntervalSince1970:t / 1000000.0]; }
};

struct SVNrevision : svn_opt_revision_t {
	SVNrevision()							{ kind = svn_opt_revision_unspecified; value.number = 0; }
	SVNrevision(svn_opt_revision_kind k)	{ kind = k;	value.number = 0;	}
	SVNrevision(svn_revnum_t n)				{ kind = svn_opt_revision_number; value.number = n; }
	SVNrevision(SVNdate d)					{ kind = svn_opt_revision_date; value.date = d;		}
	SVNrevision(NSNumber *n)				{ kind = svn_opt_revision_number; value.number = [n unsignedLongLongValue]; }
	
	SVNrevision&	operator--()			{ --value.number; return *this;			}
	
	static SVNrevision unspecified()		{ return svn_opt_revision_unspecified;	}
	static SVNrevision committed()			{ return svn_opt_revision_committed;	}
	static SVNrevision previous()			{ return svn_opt_revision_previous;		}
	static SVNrevision base()				{ return svn_opt_revision_base;			}
	static SVNrevision working()			{ return svn_opt_revision_working;		}
	static SVNrevision head()				{ return svn_opt_revision_head;			}
	static SVNrevision start()				{ return svn_opt_revision_number;		}
};

struct SVNrevisionrange : svn_opt_revision_range_t {
	SVNrevisionrange(const svn_opt_revision_t &_start, const svn_opt_revision_t &_end) {
		start	= _start;
		end		= _end;
	}
};

struct SVNStatus {
	typedef enum svn_wc_status_kind status;
	svn_node_kind_t kind;
	status			node_status, text_status, prop_status;
	svn_revnum_t	changed_rev;
	apr_time_t		changed_date;
	NSString		*lock_owner;
	
	void	init(svn_node_kind_t _kind,
		status			_node_status,
		status			_text_status,
		status			_prop_status,
		const svn_lock_t *_lock,
		svn_revnum_t	_changed_rev,
		apr_time_t		_changed_date
	) {
		node_status		= _node_status;
		text_status		= _text_status;
		prop_status		= _prop_status;
		lock_owner		= _lock ? [[NSString stringWithUTF8String:_lock->owner] retain] : nil;
		changed_rev		= _changed_rev;
		changed_date	= _changed_date;
	}
	void	dealloc() {
		if (lock_owner)
			[lock_owner release];
	}
};

@interface SVNClientStatus : NSObject {
@public
	NSString		*path;
	NSString		*changelist;
	svn_filesize_t	filesize;
	svn_revnum_t	base_rev;
	bool			conflicted;
	SVNStatus		local, repos;
}

+(SVNClientStatus*)createWithCType: (const svn_client_status_t*)status;
-(SVNClientStatus*)initWithCType: (const svn_client_status_t*)status;

-(NSString*)path;
-(NSString*)lock;
-(NSString*)text_status;
-(NSString*)prop_status;
@end

@interface SVNClientInfo : NSObject {
@public
	NSString*			URL;
	NSString*			repos_root_URL;
	NSString*			repos_UUID;

	svn_revnum_t		rev;
	svn_node_kind_t		kind;
	svn_filesize_t		size;
	svn_revnum_t		last_changed_rev;
	apr_time_t			last_changed_date;
	NSString*			last_changed_author;
	
//	const svn_lock_t	*lock;
//	const svn_wc_info_t	*wc_info;
}

+(SVNClientInfo*)createWithCType: (const svn_client_info2_t*)info;
-(SVNClientInfo*)initWithCType: (const svn_client_info2_t*)info;

@end

//------------------------------------------------------------------------------
//	SVNstream
//------------------------------------------------------------------------------

struct SVNstreamFILE {
	typedef long long offset;
	FILE		*file;
	
	size_t		read(char *buffer, size_t len)		{ return fread(buffer, 1, len, file);	}
	void		skip(size_t len)					{ fseek(file, len, SEEK_CUR);			}
	size_t		write(const char *data, size_t len)	{ return fwrite(data, 1, len, file);	}
	void		close()								{ fclose(file); file = 0;				}
	offset		tell()								{ return ftell(file);					}
	void		seek(offset o)						{ fseek(file, o, SEEK_SET);				}
	
	SVNstreamFILE(const char *fn) {
		file = fopen(fn, "w");
	}
	~SVNstreamFILE() {
		if (file)
			fclose(file);
	}
};

template<typename T> class SVNstream : APR {
	typedef	typename T::offset offset;
	static svn_error_t *_read(void *baton, char *buffer, apr_size_t *len) {
		*len = ((T*)baton)->read(buffer, *len);
		return 0;
	}
	static svn_error_t *_skip(void *baton, apr_size_t len) {
		((T*)baton)->skip(len);
		return 0;
	}
	static svn_error_t *_write(void *baton, const char *data, apr_size_t *len) {
		*len = ((T*)baton)->write(data, *len);
		return 0;
	}
	static svn_error_t *_close(void *baton) {
		((T*)baton)->close();
		return 0;
	}
	static svn_error_t *_mark(void *baton, svn_stream_mark_t **mark, apr_pool_t *pool) {
		offset	*o = new(pool) offset;
		*o		= ((T*)baton)->tell();
		*mark	= (svn_stream_mark_t*)o;
		return 0;
	}
	static svn_error_t *_seek(void *baton, const svn_stream_mark_t *mark) {
		((T*)baton)->seek(*(offset*)mark);
		return 0;
	}
	
	svn_stream_t	*s;
public:
	SVNstream(const T &t) {
		s = svn_stream_create((void*)&t, pool);
		svn_stream_set_read(s, _read);
		svn_stream_set_skip(s, _skip);
		svn_stream_set_write(s, _write);
		svn_stream_set_close(s, _close);
		svn_stream_set_mark(s, _mark);
		svn_stream_set_seek(s, _seek);
	}
	~SVNstream() {
		svn_stream_disown(s, pool);
	}
	operator svn_stream_t*() const { return s; }
};

struct SVNfile : APR {
	svn_stream_t	*s;
public:
	SVNfile(const char *path) {
		svn_stream_open_writable(&s, path, pool, pool);
	}
	~SVNfile() {
		svn_stream_disown(s, pool);
	}
	operator svn_stream_t*() const { return s; }
};

//------------------------------------------------------------------------------
//	SVN_blame_info
//------------------------------------------------------------------------------

struct SVN_blame_info {
	svn_revnum_t	rev_start, rev_end;
	
	apr_int64_t		line_no;
	svn_revnum_t	revision;
	APRhash			props;

	svn_revnum_t	rev_merged;
	APRhash			props_merged;
	const char		*path_merged;
	
	const char		*line;
	bool			local_change;
	
	SVN_blame_info(svn_revnum_t _rev_start, svn_revnum_t _rev_end
		, apr_int64_t _line_no, svn_revnum_t _revision, apr_hash_t *_props
		, svn_revnum_t _rev_merged, apr_hash_t *_props_merged, const char *_path_merged
		, const char *_line, svn_boolean_t _local_change
	)	: rev_start(_rev_start), rev_end(_rev_end)
		, line_no(_line_no), revision(_revision), props(_props)
		, rev_merged(_rev_merged), props_merged(_props_merged), path_merged(_path_merged)
		, line(_line), local_change(_local_change)
	{}
};

//------------------------------------------------------------------------------
//	SVNauthority
//------------------------------------------------------------------------------

template<typename T> class SVNauthority : svn_auth_provider_object_t {
	static svn_auth_provider_t*	get_vtable() {
		static svn_auth_provider_t vtable = {
			T::kind(),
			cb_first_credentials,
			cb_next_credentials,
			cb_save_credentials
		};
		return &vtable;
	}
	static svn_error_t *cb_first_credentials(void **credentials, void **iter_baton, void *provider_baton, apr_hash_t *parameters, const char *realm, apr_pool_t *pool) {
		return ((T*)provider_baton)->first_credentials(credentials, iter_baton, parameters, realm, pool);
	}
	static svn_error_t *cb_next_credentials(void **credentials, void *iter_baton, void *provider_baton, apr_hash_t *parameters, const char *realm, apr_pool_t *pool) {
		return ((T*)provider_baton)->next_credentials(credentials, iter_baton, parameters, realm, pool);
	}
	static svn_error_t *cb_save_credentials(svn_boolean_t *saved, void *credentials, void *provider_baton, apr_hash_t *parameters, const char *realm, apr_pool_t *pool) {
		return ((T*)provider_baton)->save_credentials(saved, credentials, parameters, realm, pool);
	}
public:
	SVNauthority(T *t) {
		vtable = get_vtable();
		provider_baton = t;
	}
	const svn_auth_provider_object_t	*operator&() const	{ return this; }
};

//------------------------------------------------------------------------------
//	SVNcontext
//------------------------------------------------------------------------------

@protocol SVNdelegate
@optional
-(NSWindow*)	window;
-(void)			SVNnotify:	(const svn_wc_notify_t*)notify pool:(apr_pool_t*)pool;
-(void)			SVNprogress:(apr_off_t)progress total:(apr_off_t)total pool:(apr_pool_t*)pool;
-(svn_error_t*)	SVNcancel;
-(svn_error_t*)	SVNstatus:	(const svn_client_status_t*)status path:(const char*)path pool:(apr_pool_t*)pool;
-(svn_error_t*)	SVNprops:	(const APRhash&)props path:(const char*)path pool:(apr_pool_t*)pool;
-(svn_error_t*)	SVNcommit:	(const svn_commit_info_t*)commit_info pool:(apr_pool_t*)pool;
-(svn_error_t*)	SVNinfo:	(const svn_client_info2_t*)info path:(const char*)path pool:(apr_pool_t*)pool;
-(svn_error_t*)	SVNlog:		(svn_log_entry_t*)log_entry pool:(apr_pool_t*)pool;
-(svn_error_t*)	SVNlist:	(const svn_dirent_t*) dirent path:(const char*)path abspath:(const char*)abs_path lock:(const svn_lock_t*)lock pool:(apr_pool_t*)pool;
-(svn_error_t*)	SVNblame:	(const SVN_blame_info&)blame_info pool:(apr_pool_t*)pool;
@end

template<typename T> class ref_ptr {
	T	*p;
public:
	ref_ptr(T *_p = 0)			{ if ((p = _p)) p->addref();	}
	~ref_ptr()					{ if (p) p->release();			}
	void	operator=(T *_p)	{ if (p) p->release(); if ((p = _p)) p->addref(); }
	operator	T*()	const	{ return p; }
	T*	operator->()	const	{ return p; }
	
};

template<typename T> class refs {
friend class ref_ptr<T>;
	int		n;
protected:
	refs() : n(0)		{}
	~refs()				{ assert(n == 0); }
	void	addref()	{ ++n; }
	void	release()	{ if (!--n) delete static_cast<T*>(this); }
};

class SVNcontext : public refs<SVNcontext>, APRInit {
	svn_error_t	*simple_prompt(svn_auth_cred_simple_t **cred, const char *realm,const char *username,svn_boolean_t may_save, apr_pool_t *pool);
	svn_error_t	*username_prompt(svn_auth_cred_username_t **cred, const char *realm,svn_boolean_t may_save, apr_pool_t *pool);
	svn_error_t	*ssl_server_trust_prompt(svn_auth_cred_ssl_server_trust_t **cred, const char *realm, apr_uint32_t failures,const svn_auth_ssl_server_cert_info_t *cert_info,svn_boolean_t may_save,apr_pool_t *pool);
	svn_error_t	*ssl_client_cert_prompt(svn_auth_cred_ssl_client_cert_t **cred, const char *realm,svn_boolean_t may_save, apr_pool_t *pool);
	svn_error_t	*ssl_client_cert_pw_prompt(svn_auth_cred_ssl_client_cert_pw_t **cred, const char *realm,svn_boolean_t may_save, apr_pool_t *pool);
	svn_error_t	*plaintext_prompt(svn_boolean_t *may_save_plaintext, const char *realm, apr_pool_t *pool);
	svn_error_t	*plaintext_passphrase_prompt(svn_boolean_t *may_save_plaintext, const char *realm, apr_pool_t *pool);

	static svn_error_t	*_cb_simple_prompt(svn_auth_cred_simple_t **cred,void *baton,const char *realm,const char *username,svn_boolean_t may_save,apr_pool_t *pool) {
		return ((SVNcontext*)baton)->simple_prompt(cred, realm, username, may_save, pool);
	}
	static svn_error_t	*_cb_username_prompt(svn_auth_cred_username_t **cred,void *baton,const char *realm,svn_boolean_t may_save, apr_pool_t *pool) {
		return ((SVNcontext*)baton)->username_prompt(cred, realm, may_save, pool);
	}
	static svn_error_t	*_cb_ssl_server_trust_prompt(svn_auth_cred_ssl_server_trust_t **cred,void *baton,const char *realm,apr_uint32_t failures,const svn_auth_ssl_server_cert_info_t *cert_info,svn_boolean_t may_save,apr_pool_t *pool) {
		return ((SVNcontext*)baton)->ssl_server_trust_prompt(cred, realm, failures, cert_info, may_save, pool);
	}
	static svn_error_t	*_cb_ssl_client_cert_prompt(svn_auth_cred_ssl_client_cert_t **cred,void *baton,const char *realm,svn_boolean_t may_save,apr_pool_t *pool) {
		return ((SVNcontext*)baton)->ssl_client_cert_prompt(cred, realm, may_save, pool);
	}
	static svn_error_t	*_cb_ssl_client_cert_pw_prompt(svn_auth_cred_ssl_client_cert_pw_t **cred,void *baton,const char *realm,svn_boolean_t may_save,apr_pool_t *pool) {
		return ((SVNcontext*)baton)->ssl_client_cert_pw_prompt(cred, realm, may_save, pool);
	}
	static svn_error_t	*_cb_plaintext_prompt(svn_boolean_t *may_save_plaintext,const char *realm,void *baton,apr_pool_t *pool) {
		return ((SVNcontext*)baton)->plaintext_prompt(may_save_plaintext,realm, pool);
	}
	static svn_error_t	*_cb_plaintext_passphrase_prompt(svn_boolean_t *may_save_plaintext,const char *realm,void *baton,apr_pool_t *pool) {
		return ((SVNcontext*)baton)->plaintext_passphrase_prompt(may_save_plaintext, realm, pool);
	}

	static void			_cb_notify(void *baton, const svn_wc_notify_t *notify, apr_pool_t *pool) {
		return [(NSObject<SVNdelegate>*)baton SVNnotify:notify pool:pool];
	}
	static void			_cb_progress(apr_off_t progress, apr_off_t total, void *baton, apr_pool_t *pool) {
		return [(NSObject<SVNdelegate>*)baton SVNprogress:progress total:total pool:pool];
	}
	static svn_error_t*	_cb_cancel(void *baton) {
		return [(NSObject<SVNdelegate>*)baton SVNcancel];
	}
	static svn_error_t* _cb_status(void *baton, const char *path, const svn_client_status_t *status, apr_pool_t *scratch_pool) {
		return [(NSObject<SVNdelegate>*)baton SVNstatus:status path:path pool:scratch_pool];
	}
	static svn_error_t*	_cb_props(void *baton, const char *path, apr_hash_t *props, apr_pool_t *pool) {
		return [(NSObject<SVNdelegate>*)baton SVNprops:props path:path pool:pool];
	}
	static svn_error_t* _cb_commit(const svn_commit_info_t *commit_info, void *baton, apr_pool_t *pool) {
		return [(NSObject<SVNdelegate>*)baton SVNcommit:commit_info pool:pool];
	}
	static svn_error_t*	_cb_logentry(void *baton, svn_log_entry_t *log_entry, apr_pool_t *pool) {
		return [(NSObject<SVNdelegate>*)baton SVNlog:log_entry pool:pool];
	}
	static svn_error_t* _cb_info(void *baton, const char *path, const svn_client_info2_t *info, apr_pool_t *scratch_pool) {
		return [(NSObject<SVNdelegate>*)baton SVNinfo:info path:path pool:pool];
	}
	static svn_error_t* _cb_blame(void *baton, svn_revnum_t rev_start, svn_revnum_t rev_end,
		apr_int64_t line_no, svn_revnum_t revision, apr_hash_t *props,
		svn_revnum_t rev_merged, apr_hash_t *props_merged, const char *path_merged,
		const char *line, svn_boolean_t local_change, apr_pool_t *pool)
	{
		return [(NSObject<SVNdelegate>*)baton SVNblame:SVN_blame_info(
			rev_start, rev_end,
			line_no, revision, props,
			rev_merged, props_merged, path_merged,
			line, local_change
		) pool:pool];
	}
	static svn_error_t *_cb_list(void *baton, const char *path, const svn_dirent_t *dirent, const svn_lock_t *lock, const char *abs_path, apr_pool_t *pool) {
		return [(NSObject<SVNdelegate>*)baton SVNlist:dirent path:path abspath:abs_path lock:lock pool:pool];
	}

	static svn_error_t* __cb_info(void *baton, const char *path, const svn_client_info2_t *info, apr_pool_t *scratch_pool) {
		*(const svn_client_info2_t**)baton = info;
		return 0;
	}
	static svn_error_t*	__cb_log(const char **log_msg, const char **tmp_file, const apr_array_header_t *commit_items, void *baton, apr_pool_t *pool) {
		*log_msg = baton ? [(NSString*)baton UTF8String] : "";
		return 0;
	}
	
protected:
	svn_client_ctx_t	*ctx;
	svn_revnum_t		result_rev;
	NSWindow			*window;

	struct SetDelegate {
		SVNcontext	*svn;
		SetDelegate(SVNcontext *_svn, NSObject<SVNdelegate> *delegate, NSString *comment = nil);
		~SetDelegate();
	};
	
	struct WithWindowStruct {
		SVNcontext	*svn;
		WithWindowStruct(SVNcontext *_svn, NSWindow *_window) : svn(_svn) { svn->window = _window; }
		~WithWindowStruct()			{ svn->window = nil; }
		SVNcontext*	operator->()	{ return svn; }
	};


public:
	static NSString *GetErrorMessage(const svn_error_t *err, bool = false);
	static void		LogErrorMessage(const svn_error_t *err);
	
	WithWindowStruct	WithWindow(NSWindow *_window) {
		return WithWindowStruct(this, _window);
	}

	NSString*	GetWCRoot(NSString *path) {
		const char *root = 0;
		if (svn_client_get_wc_root(&root,
			[path UTF8String],
			ctx, pool, pool
		))
			return nil;
		return [NSString stringWithUTF8String:root];
	}

	svn_error_t*	Update(NSObject<SVNdelegate> *delegate, NSArray *paths, APRarray<svn_revnum_t> &revs, const SVNrevision &revision, svn_depth_t depth = svn_depth_infinity) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_update4(
			&revs,
			APRpaths(paths),
			&revision,
			depth,
			FALSE,	//depth_is_sticky
			FALSE,	//ignore_externals
			TRUE,	//allow_unver_obstructions
			TRUE,	//adds_as_modification
			FALSE,	//make_parents
			ctx, pool
		);
	}

	svn_error_t*	Commit(NSObject<SVNdelegate> *delegate, NSArray *paths, NSString *comment, svn_depth_t depth = svn_depth_infinity) {
		SetDelegate	setdelegate(this, delegate, comment);
		return svn_client_commit5(
			APRpaths(paths),
			depth,
			FALSE,	//keep_locks,
			FALSE,	//keep_changelists,
			FALSE,	//commit_as_operations,
			NULL,	//changelists,
			NULL,	//revprop_table,
			[delegate respondsToSelector:@selector(SVNcommit:pool:)] ? _cb_commit : 0, delegate,
			ctx, pool
		);
	}
	svn_error_t*	Lock(NSObject<SVNdelegate> *delegate, NSArray *paths, NSString *comment, bool steal) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_lock(
			APRpaths(paths),
			[comment UTF8String],
			steal,
			ctx, pool
		);
	}

	svn_error_t*	Unlock(NSObject<SVNdelegate> *delegate, NSArray *paths, bool breaklocks) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_unlock(
			APRpaths(paths),
			breaklocks,
			ctx, pool
		);
	}

	svn_error_t*	Add(NSObject<SVNdelegate> *delegate, NSString *path, svn_depth_t depth = svn_depth_infinity) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_add4(
			[path UTF8String],
			depth,
			FALSE,	//force,
			FALSE,	//no_ignore,
			TRUE,	//add_parents,
			ctx, pool
		);
	}
	
	svn_error_t*	Delete(NSObject<SVNdelegate> *delegate, NSArray *paths) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_delete4(
			APRpaths(paths),
			FALSE,	//force,
			FALSE,	//keep_local,
			NULL,	//revprop_table,
			[delegate respondsToSelector:@selector(SVNcommit:pool:)] ? _cb_commit : 0, delegate,
			ctx, pool
		);
	}

	svn_error_t*	Copy(NSObject<SVNdelegate> *delegate, NSArray *paths, NSString *dest, const SVNrevision &revision) {
		SetDelegate	setdelegate(this, delegate);
		SVNrevision	peg;
		APRarray<svn_client_copy_source_t*>	source;
		for (NSString *i in paths) {
			svn_client_copy_source_t	*copy = new(pool) svn_client_copy_source_t;
			copy->path			= [i UTF8String];
			copy->revision		= &revision;
			copy->peg_revision	= &revision;
			source.push_back(copy);
		}
		return svn_client_copy6(
			source,
			[dest UTF8String],
			TRUE,	//copy_as_child,
			TRUE,	//make_parents,
			FALSE,	//ignore_externals,
			NULL,	//revprop_table,
			[delegate respondsToSelector:@selector(SVNcommit:pool:)] ? _cb_commit : 0, delegate,
			ctx, pool
		);
	}

	svn_error_t*	Move(NSObject<SVNdelegate> *delegate, NSArray *paths, NSString *dest) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_move6(
			APRpaths(paths),
			[dest UTF8String],
			TRUE,	//move_as_child,
			TRUE,	//make_parents,
			NULL,	//revprop_table,
			[delegate respondsToSelector:@selector(SVNcommit:pool:)] ? _cb_commit : 0, delegate,
			ctx, pool
		);
	}

	svn_error_t*	Rename(NSObject<SVNdelegate> *delegate, NSString *path, NSString *dest) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_move6(
			APRpaths(path),
			[dest UTF8String],
			FALSE,	//move_as_child,
			FALSE,	//make_parents,
			NULL,	//revprop_table,
			[delegate respondsToSelector:@selector(SVNcommit:pool:)] ? _cb_commit : 0, delegate,
			ctx, pool
		);
	}

	svn_error_t*	MakeDirs(NSObject<SVNdelegate> *delegate, NSArray *paths) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_mkdir4(
			APRpaths(paths),
			TRUE,	//make_parents,
			NULL,	//revprop_table,
			[delegate respondsToSelector:@selector(SVNcommit:pool:)] ? _cb_commit : 0, delegate,
			ctx, pool
		);
	}

	svn_error_t*	Revert(NSObject<SVNdelegate> *delegate, NSArray *paths, svn_depth_t depth = svn_depth_infinity) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_revert2(
			APRpaths(paths),
			depth,
			NULL,	//changelists,
			ctx, pool
		);
	}

	svn_error_t*	Resolve(NSObject<SVNdelegate> *delegate, NSString *path, svn_depth_t depth = svn_depth_infinity, svn_wc_conflict_choice_t conflict = svn_wc_conflict_choose_merged) {
		return svn_client_resolve(
			[path UTF8String],
			depth,
			conflict,
			ctx, pool
		);
	}
	
	svn_error_t*	Cleanup(NSObject<SVNdelegate> *delegate, NSString *path) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_cleanup([path UTF8String], ctx, pool);
	}

	svn_error_t*	Upgrade(NSObject<SVNdelegate> *delegate, NSString *path) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_upgrade([path UTF8String], ctx, pool);
	}
	
	svn_error_t*	GetStatus(NSObject<SVNdelegate> *delegate, NSString *path, const SVNrevision &revision, svn_depth_t depth = svn_depth_infinity, bool get_all = false) {
		svn_revnum_t	rev_num;
		return svn_client_status5(
			&rev_num,
			ctx,
			[path UTF8String],
			&revision,
			depth,
			get_all,//get_all,
			TRUE,	//update,
			FALSE,	//no_ignore,
			FALSE,	//ignore_externals,
			FALSE,	//depth_as_sticky,
			NULL,	//changelists,
			[delegate respondsToSelector:@selector(SVNstatus:path:pool:)] ? _cb_status : 0, delegate,
			pool
		);
	}
	svn_error_t*	GetLog(NSObject<SVNdelegate> *delegate, NSArray *paths, const APRarray<SVNrevisionrange*> &revs, int limit) {
		SVNrevision	peg;
		return svn_client_log5(
			APRpaths(paths),
			&peg,
			revs,
			limit,
			TRUE,	//discover_changed_paths,
			TRUE,	//strict_node_history,
			FALSE,//TRUE,	//include_merged_revisions,
			NULL,	//revprops,
			[delegate respondsToSelector:@selector(SVNlog:pool:)] ? _cb_logentry : 0, delegate,
			ctx, pool
		);
	}
	
	APRhash	GetRevProps(NSString *path, SVNrevision revision) {
		apr_hash_t		*props = 0;
		svn_revnum_t	set_rev;
		svn_client_revprop_list(
			&props,
			[path UTF8String],
			&revision,
			&set_rev,
			ctx, pool
		);
		return props;
	}

	svn_error_t*	GetProps(NSObject<SVNdelegate> *delegate, NSString *path, SVNrevision revision = SVNrevision(), svn_depth_t depth = svn_depth_empty) {
		return svn_client_proplist3(
			[path UTF8String],
			&revision, &revision,
			depth,
			NULL,	//changelists,
			[delegate respondsToSelector:@selector(SVNprops:path:pool:)] ? _cb_props : 0, delegate,
			ctx, pool
		);
	}
	
	svn_error_t*	SetProp(NSObject<SVNdelegate> *delegate, NSArray *paths, NSString *prop, NSData *value, svn_depth_t depth = svn_depth_empty) {
		SetDelegate	setdelegate(this, delegate);
		return svn_client_propset_local(
			[prop UTF8String],
			value ? [value SVNStringWithPool:pool] : NULL,
			APRpaths(paths),
			depth,
			FALSE,	//skip_checks,
			NULL,	//changelists,
			ctx, pool
		);
	}

	svn_error_t*	Blame(NSObject<SVNdelegate> *delegate, NSString *path, const SVNrevision &rev_start, const SVNrevision &rev_end) {
		svn_diff_file_options_t	opts = {
			svn_diff_file_ignore_space_none,	//svn_diff_file_ignore_space_t ignore_space;
			TRUE,								//svn_boolean_t ignore_eol_style;
			FALSE,								//show_c_function;
		};
		SVNrevision	peg;
		return svn_client_blame5(
			[path UTF8String],
			&peg,
			&rev_start, &rev_end,
			&opts,
			TRUE,	// ignore_mime_type,
			FALSE,	// include_merged_revisions,
			[delegate respondsToSelector:@selector(SVNblame:pool:)] ? _cb_blame : 0, delegate,
			ctx, pool
		);
	}

	svn_error_t*	GetDiffs(NSString *output, NSString *path1, const SVNrevision &revision1, NSString *path2, const SVNrevision &revision2, svn_depth_t depth = svn_depth_empty) {
		APRfile	outfile;
		outfile.open([output UTF8String], APR_FOPEN_CREATE | APR_FOPEN_WRITE);

		return svn_client_diff5(
			NULL,	//const apr_array_header_t * 	diff_options,
			[path1 UTF8String], &revision1,
			[path2 UTF8String], &revision2,
			NULL,	//relative_to_dir,
			depth,
			FALSE,	//ignore_ancestry,
			TRUE,	//no_diff_deleted,
			FALSE,	//show_copies_as_adds,
			FALSE,	//ignore_content_type,
			FALSE,	//use_git_diff_format,
			"",		//const char * 	header_encoding,
			outfile,
			APRfile::stderr(),
			NULL,	//changelists
			ctx, pool
		);
	}

	svn_error_t*	GetInfo(NSObject<SVNdelegate> *delegate, NSString *path, const SVNrevision &revision, svn_depth_t depth = svn_depth_empty) {
		SVNrevision	peg;
		return svn_client_info3(
			[path UTF8String],
			&peg,
			&revision,
			depth,
			FALSE,	//fetch_excluded,
			FALSE,	//fetch_actual_only,
			NULL,	//changelists,
			_cb_info, delegate,
			ctx, pool
		);
	}
	svn_error_t*	GetInfo(NSString *path, const SVNrevision &revision, svn_client_info2_t **info) {
		SVNrevision	peg;
		return svn_client_info3(
			[path UTF8String],
			&peg,
			&revision,
			svn_depth_empty,
			FALSE,	//fetch_excluded,
			FALSE,	//fetch_actual_only,
			NULL,	//changelists,
			__cb_info, 	info,
			ctx, pool
		);
	}

	svn_error_t*	GetFile(NSString *output, NSString *input, const SVNrevision &revision) {
		SVNrevision	peg;
		return svn_client_cat2(
			SVNfile([output UTF8String]),
			[input UTF8String],
			&peg,
			&revision,
			ctx, pool
		);
	}
	template<typename T> svn_error_t* GetFile(const T &output, NSString *input, const SVNrevision &revision) {
		SVNrevision	peg(revision);
		return svn_client_cat2(
			SVNstream<T>(output),
			[input UTF8String],
			&peg,
			&revision,
			ctx, pool
		);
	}
	
	svn_error_t*	GetList(NSObject<SVNdelegate> *delegate, NSString *path, const SVNrevision &revision, svn_depth_t depth = svn_depth_immediates) {
		SVNrevision	peg;
		return svn_client_list2(
			[path UTF8String],
			&peg,
			&revision,
			depth,
			SVN_DIRENT_ALL,		//dirent_fields,
			TRUE,				//fetch_locks,
			[delegate respondsToSelector:@selector(SVNlist:path:abspath:lock:pool:)] ? _cb_list : 0, delegate,
			ctx, pool
		);
	}
	
	svn_error_t*	Checkout(NSObject<SVNdelegate> *delegate, NSString *from_path, NSString *to_path, SVNrevision revision = SVNrevision::head(), svn_depth_t depth = svn_depth_infinity) {
		SetDelegate	setdelegate(this, delegate);
		SVNrevision	peg;
		return svn_client_checkout3(
			&result_rev,
			[from_path UTF8String],
			[to_path UTF8String],
			&peg,
			&revision,
			depth,
			FALSE,	//ignore_externals,
			FALSE,	//allow_unver_obstructions,
			ctx, pool
		);
	}
	
	svn_error_t*	MakeDir(NSObject<SVNdelegate> *delegate, NSString *path, NSString *comment = nil) {
		SetDelegate	setdelegate(this, delegate, comment);
		return svn_client_mkdir4(
			APRpaths(path),
			FALSE,	//svn_boolean_t make_parents,
			NULL,	//const apr_hash_t *revprop_table,
			[delegate respondsToSelector:@selector(SVNcommit:pool:)] ? _cb_commit : 0, delegate,
			ctx, pool
		);
	}
	
	svn_error_t*	Import(NSObject<SVNdelegate> *delegate, NSString *from_path, NSString *to_path, NSString *comment = nil, svn_depth_t depth = svn_depth_infinity) {
		if ([from_path isDir])
			MakeDir(delegate, to_path, comment);
			
		SetDelegate	setdelegate(this, delegate, comment);
		svn_error_t *err = svn_client_import4(
			[from_path UTF8String],
			[to_path UTF8String],
			depth,
			FALSE,	//no_ignore,
			FALSE,	//ignore_unknown_node_types,
			NULL,	//revprop_table,
			[delegate respondsToSelector:@selector(SVNcommit:pool:)] ? _cb_commit : 0, delegate,
			ctx, pool
		);
		return err;
	}

	SVNcontext();
	~SVNcontext();
};

//------------------------------------------------------------------------------
//	SVNdiff
//------------------------------------------------------------------------------

struct SVNDiffSpan {
	apr_off_t start, length;
	SVNDiffSpan(apr_off_t _start, apr_off_t _length) : start(_start), length(_length) {}
};

struct SVNDiffPacket {
	SVNDiffSpan	original, modified, latest;
	SVNDiffPacket(
		apr_off_t original_start,
		apr_off_t original_length,
		apr_off_t modified_start,
		apr_off_t modified_length,
		apr_off_t latest_start,
		apr_off_t latest_length
	)	: original(original_start, original_length)
		, modified(modified_start, modified_length)
		, latest(latest_start, latest_length)
	{}
};

template<typename T> class SVNdatasources : public svn_diff_fns2_t {
	static svn_error_t*	cb_open(void *baton, apr_off_t *prefixes, apr_off_t *suffixes, const svn_diff_datasource_e *sources, apr_size_t num_sources) {
		return ((T*)baton)->open(prefixes, suffixes, sources, num_sources);
	}
	static svn_error_t*	cb_close(void *baton, svn_diff_datasource_e source) {
		return ((T*)baton)->close(source);
	}
	static svn_error_t*	cb_get_next_token(apr_uint32_t *hash, void **token, void *baton, svn_diff_datasource_e source) {
		return ((T*)baton)->get_next_token(hash, token, source);
	}
	static svn_error_t*	cb_compare(void *baton, void *ltoken, void *rtoken, int *cmp) {
		return ((T*)baton)->compare(ltoken, rtoken, cmp);
	}
	static void			cb_discard(void *baton, void *token) {
		return ((T*)baton)->discard(token);
	}
	static void			cb_discard_all(void *baton) {
		return ((T*)baton)->discard_all();
	}
public:
	SVNdatasources() {
		datasources_open			= cb_open;
		datasource_close			= cb_close;
		datasource_get_next_token	= cb_get_next_token;
		token_compare				= cb_compare;
		token_discard				= cb_discard;
		token_discard_all			= cb_discard_all;
	}
	const svn_diff_fns2_t	*operator&() const	{ return this; }
};

template<typename T> class SVNdiffoutput : public svn_diff_output_fns_t {
	static svn_error_t *cb_common(void *baton,
		apr_off_t original_start,
		apr_off_t original_length,
		apr_off_t modified_start,
		apr_off_t modified_length,
		apr_off_t latest_start,
		apr_off_t latest_length) {
		return ((T*)baton)->common(
			SVNDiffPacket(original_start,original_length,modified_start,modified_length,latest_start,latest_length)
		);
	}
	static svn_error_t *cb_diff_modified(void *baton,
		apr_off_t original_start,
		apr_off_t original_length,
		apr_off_t modified_start,
		apr_off_t modified_length,
		apr_off_t latest_start,
		apr_off_t latest_length) {
		return ((T*)baton)->diff_modified(
			SVNDiffPacket(original_start,original_length,modified_start,modified_length,latest_start,latest_length)
		);
	}
	static svn_error_t *cb_diff_latest(void *baton,
		apr_off_t original_start,
		apr_off_t original_length,
		apr_off_t modified_start,
		apr_off_t modified_length,
		apr_off_t latest_start,
		apr_off_t latest_length) {
		return ((T*)baton)->diff_latest(
			SVNDiffPacket(original_start,original_length,modified_start,modified_length,latest_start,latest_length)
		);
	}
	static svn_error_t *cb_diff_common(void *baton,
		apr_off_t original_start,
		apr_off_t original_length,
		apr_off_t modified_start,
		apr_off_t modified_length,
		apr_off_t latest_start,
		apr_off_t latest_length) {
		return ((T*)baton)->diff_common(
			SVNDiffPacket(original_start,original_length,modified_start,modified_length,latest_start,latest_length)
		);
	}
	static svn_error_t *cb_conflict(void *baton,
		apr_off_t original_start,
		apr_off_t original_length,
		apr_off_t modified_start,
		apr_off_t modified_length,
		apr_off_t latest_start,
		apr_off_t latest_length,
		svn_diff_t *resolved_diff) {
		return ((T*)baton)->conflict(
			SVNDiffPacket(original_start,original_length,modified_start,modified_length,latest_start,latest_length),
			resolved_diff
		);
	}
public:
	SVNdiffoutput() {
		output_common			= cb_common;
		output_diff_modified	= cb_diff_modified;
		output_diff_latest		= cb_diff_latest;
		output_diff_common		= cb_diff_common;
		output_conflict			= cb_conflict;
	}
	const svn_diff_output_fns_t	*operator&() const	{ return this; }
};

@protocol SVNdatasource_delegate
-(svn_error_t*)	SVNdatasource_open:			(const svn_diff_datasource_e*)sources	num:(apr_size_t)num_sources prefixes:(apr_off_t*)prefixes suffixes:(apr_off_t*)suffixes;
-(svn_error_t*)	SVNdatasource_close:		(svn_diff_datasource_e)source;
-(svn_error_t*)	SVNdatasource_get_next_token:(void**)token source:(svn_diff_datasource_e)source hash:(apr_uint32_t*)hash;
-(svn_error_t*)	SVNdatasource_compare:		(void*)ltoken to:(void*)rtoken result:(int*)cmp;
-(void)			SVNdatasource_discard:		(void*)token;
-(void)			SVNdatasource_discard_all;
@end

struct SVNdatasource_delegator {
	NSObject<SVNdatasource_delegate> *obj() const { return (NSObject<SVNdatasource_delegate>*)this;	}
	svn_error_t*	open(apr_off_t *prefixes, apr_off_t *suffixes, const svn_diff_datasource_e *sources, apr_size_t num_sources) {
		return [obj() SVNdatasource_open:sources num:num_sources prefixes:prefixes suffixes:suffixes];
	}
	svn_error_t*	close(svn_diff_datasource_e source) {
		return [obj() SVNdatasource_close:source];
	}
	svn_error_t*	get_next_token(apr_uint32_t *hash, void **token, svn_diff_datasource_e source) {
		return [obj() SVNdatasource_get_next_token:token source:source hash:hash];
	}
	svn_error_t*	compare(void *ltoken, void *rtoken, int *cmp) {
		return [obj() SVNdatasource_compare:ltoken to:rtoken result:cmp];
	}
	void			discard(void *token)	{ [obj() SVNdatasource_discard:	token];	}
	void			discard_all()			{ [obj() SVNdatasource_discard_all];	}
};

@protocol SVNdiff_delegate
-(svn_error_t*)	SVNdiff_common:			(const SVNDiffPacket&)packet;
-(svn_error_t*)	SVNdiff_diff_modified:	(const SVNDiffPacket&)packet;
@optional
-(svn_error_t*)	SVNdiff_diff_latest:	(const SVNDiffPacket&)packet;
-(svn_error_t*)	SVNdiff_diff_common:	(const SVNDiffPacket&)packet;
-(svn_error_t*)	SVNdiff_conflict:		(const SVNDiffPacket&)packet resolved:(svn_diff_t*)resolved;
@end

struct SVNdiff_delegator {
	NSObject<SVNdiff_delegate> *obj() const { return (NSObject<SVNdiff_delegate>*)this;	}
	svn_error_t*	common			(const SVNDiffPacket &packet)	{ return [obj() SVNdiff_common:			packet]; }
	svn_error_t*	diff_modified	(const SVNDiffPacket &packet)	{ return [obj() SVNdiff_diff_modified:	packet]; }
	svn_error_t*	diff_latest		(const SVNDiffPacket &packet)	{ return [obj() SVNdiff_diff_latest:	packet]; }
	svn_error_t*	diff_common		(const SVNDiffPacket &packet)	{ return [obj() SVNdiff_diff_common:	packet]; }
	svn_error_t*	conflict		(const SVNDiffPacket &packet, svn_diff_t *resolved)	{
		return [obj() SVNdiff_conflict: packet resolved:resolved];
	}
};

class SVNdiff {
	APRpool			pool;
	svn_error_t		*err;

	struct Options : svn_diff_file_options_t {
		Options(bool _ignore_eol_style, svn_diff_file_ignore_space_t _ignore_space) {
			ignore_eol_style	= _ignore_eol_style;
			ignore_space		= _ignore_space;
			show_c_function		= false;
		}
		const svn_diff_file_options_t	*operator&() const	{ return this; }
	};
	
public:
	template<typename T> svn_diff_t *MakeDiff1(T &sources) {
		svn_error_t *svn_diff_diff_1(svn_diff_t **diff, void *diff_baton, const svn_diff_fns2_t *diff_fns, apr_pool_t *pool);
		svn_diff_t *diff = 0;
		err = svn_diff_diff_1(&diff, &sources, &SVNdatasources<T>(), pool);
		return diff;
	}
	template<typename T> svn_diff_t *MakeDiff2(T &sources) {
		svn_diff_t *diff = 0;
		err = svn_diff_diff_2(&diff, &sources, &SVNdatasources<T>(), pool);
		return diff;
	}
	template<typename T> svn_diff_t *MakeDiff3(T &sources) {
		svn_diff_t *diff = 0;
		err = svn_diff_diff3_2(&diff, &sources, &SVNdatasources<T>(), pool);
		return diff;
	}
	template<typename T> svn_diff_t *MakeDiff4(T &sources) {
		svn_diff_t *diff = 0;
		err = svn_diff_diff4_2(&diff, &sources, &SVNdatasources<T>(), pool);
		return diff;
	}

	template<typename T> svn_error_t *ProcessDiff(T &output, svn_diff_t *diff) {
		return svn_diff_output(diff, &output, &SVNdiffoutput<T>());
	}

	svn_diff_t *MakeDiff2(NSString *base, NSString *path, bool ignore_eol_style = true, svn_diff_file_ignore_space_t ignore_space = svn_diff_file_ignore_space_all) {
		svn_diff_t *diff = 0;
		err = svn_diff_file_diff_2(&diff,
			[base UTF8String], [path UTF8String],
			&Options(ignore_eol_style, ignore_space), pool
		);
		return diff;
	}
	svn_diff_t *MakeDiff3(NSString *base, NSString *path, NSString *latest, bool ignore_eol_style = true, svn_diff_file_ignore_space_t ignore_space = svn_diff_file_ignore_space_all) {
		svn_diff_t *diff = 0;
		err = svn_diff_file_diff3_2(&diff,
			[base UTF8String], [path UTF8String], [latest UTF8String],
			&Options(ignore_eol_style, ignore_space), pool
		);
		return diff;
	}
	svn_diff_t *MakeDiff4(NSString *base, NSString *path, NSString *latest, NSString *ancestor, bool ignore_eol_style = true, svn_diff_file_ignore_space_t ignore_space = svn_diff_file_ignore_space_all) {
		svn_diff_t *diff = 0;
		err = svn_diff_file_diff4_2(&diff,
			[base UTF8String], [path UTF8String], [latest UTF8String], [ancestor UTF8String],
			&Options(ignore_eol_style, ignore_space), pool
		);
		return diff;
	}
	svn_error_t *ProcessDiffObj(NSObject<SVNdiff_delegate> *obj, svn_diff_t *diff) {
		return svn_diff_output(diff, obj, &SVNdiffoutput<SVNdiff_delegator>());
	}
};


#endif
