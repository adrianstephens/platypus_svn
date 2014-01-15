#include "CoreFoundation/CFDate.h"
#include "CoreFoundation/CFTimeZone.h"

// microseconds from 00:00 1st Jan 1BC (year 0)
class DateTime {
	friend DateTime operator+(DateTime a, DateTime b) {	return a.t + b.t; }
	friend DateTime operator-(DateTime a, DateTime b) {	return a.t - b.t; }
	SInt64	t;
public:
	DateTime(SInt64 _t) : t(_t)	{}
	DateTime(int year, int day);
	DateTime(int year, int month, int day);
	static DateTime	ISO_8601(const char *p);

	int		Day()				const { return int(t / (SInt64(86400) * 1000000)); }
	float	TimeOfDay()			const { return (t % (SInt64(86400) * 1000000)) / 1000000.f; }
	operator double()			const { static DateTime cf(2001,0); return double(t - cf.t) / 1000000; }
	operator CFDateRef()		const { return CFDateCreate(NULL, *this); }
	
	DateTime	AdjustForZone(CFTimeZoneRef tz) {
		CFTimeInterval	ti = CFTimeZoneGetSecondsFromGMT(tz, *this);
		return DateTime(t + SInt64(ti * 1000000));
	}
	DateTime	AdjustForLocalZone() {
		CFTimeZoneRef	tz = CFTimeZoneCopyDefault();
		CFTimeInterval	ti = CFTimeZoneGetSecondsFromGMT(tz, *this);
		CFRelease(tz);
		return DateTime(t + SInt64(ti * 1000000));
	}
};
