#ifndef APRwrappers_h
#define APRwrappers_h

#include <apr.h>
#include <apr_pools.h>
#include <apr_hash.h>
#include <apr_tables.h>
#include <apr_getopt.h>
#include <apr_file_io.h>
#include <apr_time.h>

//------------------------------------------------------------------------------
//	APR
//------------------------------------------------------------------------------

struct APR {
	static apr_pool_t *pool;
	static void Init();
};

struct APRInit : APR {
	APRInit() { Init(); }
};

class APRpool {
	apr_pool_t *p;
public:
	APRpool(apr_pool_t *parnt = 0)	{ apr_pool_create(&p, parnt);	}
	APRpool(apr_pool_t *parnt, const char *tag)	{ apr_pool_create(&p, parnt); apr_pool_tag(p, tag); }
	~APRpool()						{ apr_pool_destroy(p);			}
	operator apr_pool_t*()	const	{ return p;						}
	APRpool	parent()		const	{ apr_pool_t *t = apr_pool_parent_get(p); return *(APRpool*)&t; }

	char	*dup(const char *s)	const	{ return apr_pstrdup(p, s); }

};

inline void *operator new(size_t size, apr_pool_t *pool) {
	return apr_palloc(pool, size);
}

//------------------------------------------------------------------------------
//	APRarray
//------------------------------------------------------------------------------

template<typename T> class APRarray : APR {
	apr_array_header_t	*h;
public:
	typedef	T*			iterator;
	typedef	const T*	const_iterator;


	APRarray(int n = 0)				: h(apr_array_make(pool, n, sizeof(T)))	{}
	APRarray(const APRarray &b)		: h(apr_array_copy_hdr(pool, b)) {}
	APRarray(const apr_array_header_t* _h): h(const_cast<apr_array_header_t*>(_h))	{}
	operator apr_array_header_t*()	const		{ return h;	}
	
	void	clear()						{ apr_array_clear(h);			}
	void	push_back(const T &t)		{ *(T*)apr_array_push(h) = t;	}
	T&		pop_back()					{ return *(T*)apr_array_pop(h);	}
	T&		operator[](int i)	const	{ return ((T*)h->elts)[i];		}
	int		size()				const	{ return h->nelts;				}
	
	iterator		begin()				{ return (T*)h->elts;			}
	iterator		end()				{ return begin() + size();		}
	const_iterator	begin()		const	{ return (const T*)h->elts;		}
	const_iterator	end()		const	{ return begin() + size();		}
	
	APRarray&	operator+=(const APRarray &b)	{ apr_array_cat(h, b); return *this; }
	apr_array_header_t**	operator&() { return &h; }
};

template<typename T> inline APRarray<T>	operator+(const APRarray<T> &a, const APRarray<T> &b) {
	APRarray<T> r;
	apr_array_append(r, a, b);
	return r;
}

struct APRpaths : APRarray<const char*> {
	APRpaths() {}
	APRpaths(const NSArray *paths) : APRarray<const char*>([paths count]) {
		for (NSString *i in paths)
			push_back([i UTF8String]);
	}
	APRpaths(const NSString *path) : APRarray<const char*>(1) {
		push_back([path UTF8String]);
	}
};

//------------------------------------------------------------------------------
//	APRhash
//------------------------------------------------------------------------------

struct any_ptr {
	void *p;
	any_ptr(void *_p) : p(_p) {}
	template<typename T> operator T*() const { return (T*)p; }
};
struct any_cptr {
	const void *p;
	any_cptr(const void *_p) : p(_p) {}
	template<typename T> operator const T*() const { return (const T*)p; }
};

class APRhash : APR {
	apr_hash_t	*h;
public:
	struct iterator {
		apr_hash_index_t	*i;
		iterator&	operator++()							{ i = apr_hash_next(i); return *this; }
		iterator	operator++(int)							{ apr_hash_index_t *t = i; i = apr_hash_next(i); return t; }
		any_ptr		operator*()	const						{ void *v; apr_hash_this(i, NULL, NULL, &v); return v; }
		bool		operator==(const iterator &b)	const	{ return i == b.i;	}
		bool		operator!=(const iterator &b)	const	{ return i != b.i;	}
		any_cptr	key(apr_ssize_t *len = 0)		const	{ const void *k; apr_hash_this(i, &k, len, NULL); return k; }

		iterator(apr_hash_index_t *_i) : i(_i) {}
	};

	APRhash()				: h(apr_hash_make(pool)) {}
	APRhash(apr_hash_t *_h) : h(_h)				{}
	operator apr_hash_t*()				const	{ return h;		}
	apr_hash_t** operator&()					{ return &h;	}

	template<typename K> void		put(const K &k, const void *v)			{ apr_hash_set(h, &k, sizeof(K), v); }
	void							put(const char *k, const void *v)		{ apr_hash_set(h, k, APR_HASH_KEY_STRING, v); }
	
	template<typename K> any_ptr	get(const K &k, const void *v)			{ return apr_hash_get(h, &k, sizeof(K)); }
	template<typename K> any_cptr	get(const K &k, const void *v)	const	{ return apr_hash_get(h, &k, sizeof(K)); }
	any_ptr							get(const char *k)						{ return apr_hash_get(h, k, APR_HASH_KEY_STRING); }
	any_cptr						get(const char *k)				const	{ return apr_hash_get(h, k, APR_HASH_KEY_STRING); }
	
	int				size()				const	{ return apr_hash_count(h); }
	iterator		begin()				const	{ return iterator(apr_hash_first(pool, h));	}
	iterator		end()				const	{ return 0;		}
};

inline APRhash	operator|(const APRhash &a, const APRhash &b) {
	return apr_hash_overlay(APR::pool, b, a);
}

//------------------------------------------------------------------------------
//	APRfile
//------------------------------------------------------------------------------

class APRfile : APR {
	apr_file_t	*file;
public:
	apr_status_t	open(const char *fname, apr_int32_t flag, apr_fileperms_t perm = APR_OS_DEFAULT) {
		return apr_file_open(&file, fname, flag, perm, pool);
	}
	apr_status_t	close()	{
		return apr_file_close(file);
	}
	apr_status_t	eof()	{
		return apr_file_eof(file);
	}
	apr_size_t		read(void *buf, apr_size_t nbytes) {
		return apr_file_read(file, buf, &nbytes) == 0 ? nbytes : 0;
	}
	apr_size_t		write(const void *buf,apr_size_t nbytes) {
		return apr_file_write(file, buf, &nbytes) == 0 ? nbytes : 0;
	}
	apr_status_t	putc(char c) {
		return apr_file_putc(c, file);
	}
	int				getc() {
		char	c;
		return apr_file_getc(&c, file) ? c : -1;
	}
	apr_status_t	ungetc(char c) {
		return apr_file_ungetc(c, file);
	}
	apr_status_t	gets(char *str, int len) {
		return apr_file_gets(str, len, file);
	}
	apr_status_t	puts(const char *str) {
		return apr_file_puts(str, file);
	}
	apr_status_t	flush() {
		return apr_file_flush(file);
	}
	apr_status_t	sync() {
		return apr_file_sync(file);
	}
	apr_status_t	datasync() {
		return apr_file_datasync(file);
	}
	apr_status_t	seek(apr_seek_where_t where,apr_off_t *offset) {
		return apr_file_seek(file, where, offset);
	}
	apr_status_t	lock(int type) {
		return apr_file_lock(file, type);
	}
	apr_status_t	unlock() {
		return apr_file_unlock(file);
	}
	apr_status_t	filename(const char **path) {
		return apr_file_name_get(path, file);
	}
	apr_status_t	trunc(apr_off_t offset) {
		return apr_file_trunc(file, offset);
	}
	apr_int32_t		flags() {
		return apr_file_flags_get(file);
	}

	static APRfile	stderr()					{ APRfile a; apr_file_open_stderr(&a.file, pool); return a; }
	static APRfile	stdout()					{ APRfile a; apr_file_open_stdout(&a.file, pool); return a; }
	static APRfile	stdin()						{ APRfile a; apr_file_open_stdin(&a.file, pool); return a; }
	static APRfile	stderr(apr_int32_t flags)	{ APRfile a; apr_file_open_flags_stderr(&a.file, flags, pool); return a; }
	static APRfile	stdout(apr_int32_t flags)	{ APRfile a; apr_file_open_flags_stdout(&a.file, flags, pool); return a; }
	static APRfile	stdin(apr_int32_t flags)	{ APRfile a; apr_file_open_flags_stdin(&a.file, flags, pool); return a; }

	APRfile() : file(0)	{}
	~APRfile()			{ if (file) close(); }
	operator apr_file_t*()	const { return file; }
};

#endif
