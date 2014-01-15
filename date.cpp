#include "date.h"

const UInt16	month_starts[]		= {0,31,59,90,120,151,181,212,243,273,304,334};

static inline bool is_digit(char c) {
	return c >= '0' && c <= '9';
}

UInt32 count_digits(const char *p) {
	const char *s = p;
	while (is_digit(*s))
		s++;
	return s - p;
}

UInt32 get_digits(const char *p, int n) {
	UInt32	r = 0;
	while (n--) {
		if (!is_digit(*p))
			return UInt32(-1);
		r = r * 10 + *p++ - '0';
	}
	return r;
};

static inline bool is_leap(int year) {
	return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}
static inline int num_leaps(int year) {
	return (year / 4) - (year / 100) + (year / 400);
}
static inline int calc_days(int year, int day) {
	return day + year * 365 + num_leaps(year - 1);
}

DateTime::DateTime(int year, int day) {
	t = SInt64(calc_days(year, day)) * 86400 * 1000000;
}

DateTime::DateTime(int year, int month, int day) {
	t = SInt64(calc_days(year, day - 1 + month_starts[month - 1]) + int(month > 2 && is_leap(year))) * 86400 * 1000000;
}

DateTime DateTime::ISO_8601(const char *p) {
	int		year	= 0;
	UInt32	day		= 0;
	UInt32	secs	= 0;
	UInt32	micro	= 0;

	if (*p == '+' || *p == '-') {
		bool	neg	= *p++ == '-';
		UInt32	n = count_digits(p);
		year	= get_digits(p, n);
		p		+= n;
		if (neg)
			year = -year;
	} else {
		year	= get_digits(p, 4);
		p += 4;
	}

	if (*p == '-')
		p++;

	if (*p == 'W') {
		UInt32	week = get_digits(p + 1, 2);
		p += 3;
		if (*p == '-')
			p++;
		day = (week - 1) * 7 + (is_digit(*p) ? *p++ - '1' : 0);

	} else if (count_digits(p) == 3) {
		day = get_digits(p, 3);
		p += 3;

	} else {
		UInt32	month = get_digits(p, 2);
		day	= month_starts[month - 1];
		if (month > 2 && is_leap(year))
			day++;

		p += 2;
		if (*p == '-')
			p++;
		if (is_digit(*p)) {
			day += get_digits(p, 2) - 1;
			p += 2;
		}
	}

	if (*p == 'T') {
		p++;
		UInt32	hour = get_digits(p, 2);
		secs	= hour * 3600;
		p += 2;
		if (*p) {
			if (*p == ':')
				p++;
			UInt32	mins = get_digits(p, 2);
			secs += mins * 60;
			p += 2;
			if (*p) {
				if (*p == ':')
					p++;
				secs += get_digits(p, 2);
				p += 2;
				if (*p == '.') {
					UInt32	n = count_digits(p + 1), n0 = n < 6 ? n : 6;
					micro = get_digits(p + 1, n0);
					while (n0 < 6)
						micro *= 10;
					p += n + 1;
				}
			}
		}
		if (*p == 'Z') {
			p++;
		} else if (*p == '+' || *p == '-') {
			bool	neg = *p++ == '-';
			UInt32	hour = get_digits(p, 2);
			UInt32	offset	= hour * 3600;
			p += 2;
			if (*p) {
				if (*p == ':')
					p++;
				UInt32	mins = get_digits(p, 2);
				offset += mins * 60;
				p += 2;
			}
			secs += neg ? offset : -offset;
		}
	}

	return (SInt64(calc_days(year, day)) * 86400 + secs) * 1000000 + micro;
};

