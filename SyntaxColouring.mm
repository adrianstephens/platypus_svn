#import <SyntaxColouring.h>

enum {
	COL_NORMAL,
	COL_COMMENT,
	COL_KEYWORD,
	COL_OPERATOR,
	COL_NUMBER,
	COL_STRING,
	COL_PREPROCESSOR,
	COL_OBJECTIVEC,
};
static rgb8 cols[] = {
	{0,		0,		0},		//NORMAL
	{0,		128,	0},		//COMMENT
	{0,		0,		128},	//KEYWORD
	{0,		0,		0},		//OPERATOR
	{128,	0,		0},		//NUMBER
	{192,	0,		0},		//STRING
	{128,	0,		128},	//PREPROCESSOR
	{128,	128,	0},		//OBJECTIVEC
};


const char *keywords[] = {
	"alignas",		//(since C++11)
	"alignof",		//(since C++11)
	"and",
	"and_eq",
	"asm",
	"auto",
	"bitand",
	"bitor",
	"bool",
	"break",
	"case",
	"catch",
	"char",
	"char16_t",		//(since C++11)
	"char32_t",		//(since C++11)
	"class",
	"compl",
	"const",
	"constexpr",	//(since C++11)
	"const_cast",
	"continue",
	"decltype",		//(since C++11)
	"default",
	"delete",
	"do",
	"double",
	"dynamic_cast",
	"else",
	"enum",
	"explicit",
	"export",
	"extern",
	"false",
	"float",
	"for",
	"friend",
	"goto",
	"if",
	"inline",
	"int",
	"long",
	"mutable",
	"namespace",
	"new",
	"noexcept",		//(since C++11)
	"not",
	"not_eq",
	"nullptr",		//(since C++11)
	"operator",
	"or",
	"or_eq",
	"private",
	"protected",
	"public",
	"register",
	"reinterpret_cast",
	"return",
	"short",
	"signed",
	"sizeof",
	"static",
	"static_assert",//(since C++11)
	"static_cast",
	"struct",
	"switch",
	"template",
	"this",
	"thread_local",	//(since C++11)
	"throw",
	"true",
	"try",
	"typedef",
	"typeid",
	"typename",
	"union",
	"unsigned",
	"using",
	"virtual",
	"void",
	"volatile",
	"wchar_t",
	"while",
	"xor",
	"xor_eq",
};

bool is_white(char c)		{ return c <= ' '; }
bool is_alpha(char c)		{ return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'); }
bool is_num(char c)			{ return c >= '0' && c <= '9';	}
bool is_alphanum(char c)	{ return is_alpha(c) || is_num(c);	}

void SetColour(NSMutableAttributedString *line, NSColor *col, NSUInteger loc, NSUInteger len) {
	if (col)
		[line addAttribute:NSForegroundColorAttributeName value:col range:NSMakeRange(loc, len)];
}

@implementation SyntaxColouring

-(void)addColours:(const char*)chars attributedString:(NSMutableAttributedString*)line {

	const char *s = chars, *p = s;
	if (comment) {
		p = strstr(s, "*/");
		if ((comment = !p))
			p = s + strlen(s);
		SetColour(line, cols[COL_COMMENT], 0, p - s);
	}
	while (char c = *p++) {
		const char *n = p - 1;
		switch (c) {
			case ' ': case '\t': continue;
			case '0':
				if (*p != '.') {
					if (*p == 'x') {
						p++;
						while ((c = *p) && (is_num(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
							p++;
					} else {
						while ((c = *p) && c >= '0' && c <= '7')
							p++;
					}
					while (c == 'u' || c == 'U' || c == 'l' || c == 'L')
						c = *++p;
					SetColour(line, cols[COL_NUMBER], n - s, p - n);
					break;
				}
			case '1': case '2': case '3': case '4': case '5':  case '6': case '7': case '8': case '9':
				while ((c = *p) && is_num(c))
					p++;
				if (c == '.') {
					p++;
					while ((c = *p) && is_num(c))
						p++;
					if (c == 'e' || c == 'E') {
						if ((c = *++p) == '+' || c == '-')
							p++;
						while ((c = *p) && is_num(c))
							p++;
					}
					if (c == 'f' || c == 'F' || c == 'l' || c == 'L')
						p++;
				} else {
					while (c == 'u' || c == 'U' || c == 'l' || c == 'L')
						c = *++p;
				}
				SetColour(line, cols[COL_NUMBER], n - s, p - n);
				break;

			case '/':
				if (*p == '/') {
					SetColour(line, cols[COL_COMMENT], n - s, strlen(p) + 1);
					p += strlen(p);
					break;
				} else if (*p == '*') {
					p = strstr(p + 1, "*/");
					if ((comment = !p))
						p = s + strlen(s);
					SetColour(line, cols[COL_COMMENT], n - s, p - n);
					break;
				}
			case '!': case '%': case '&': case '(': case ')': case '*': case '+': case ',': case '-': case '.':
			case '[': case ']': case '=': case '?': case '{': case '}': case '^': case ':': case ';': case '<': case '>':
				while ((c = *p) && !is_white(c) && !is_alphanum(c) && c != '\'' && c != '"' && c != '@')
					p++;
				SetColour(line, cols[COL_OPERATOR], n - s, p - n);
				break;

				break;
				
			case '\'': case '"':
				while (*p && *p++ != c);
				SetColour(line, cols[COL_STRING], n - s, p - n);
				break;
				
			case '#':
				while ((c = *p) && !is_white(c))
					p++;
				SetColour(line, cols[COL_PREPROCESSOR], n - s, p - n);
				break;
				
			case '@':
				while ((c = *p) && is_alphanum(c))
					p++;
				SetColour(line, cols[COL_OBJECTIVEC], n - s, p - n);
				break;
				

			default:
				while ((c = *p) && is_alphanum(c))
					p++;
				for (int i = 0; i < sizeof(keywords) / sizeof(keywords[0]); i++) {
					if (strlen(keywords[i]) == p - n && memcmp(keywords[i], n, p - n) == 0) {
						SetColour(line, cols[COL_KEYWORD], n - s, p - n);
						break;
					}
				}
				break;
		}
	}
}

-(NSMutableAttributedString*)process:(const char*)input {
	NSMutableAttributedString	*line = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithUTF8String:input]];
	[self addColours:input attributedString:line];
	return [line autorelease];
}
-(NSMutableAttributedString*)processString:(NSString*)input {
	NSMutableAttributedString	*line = [[NSMutableAttributedString alloc] initWithString:input];
	[self addColours:[input UTF8String] attributedString:line];
	return [line autorelease];
}

@end

