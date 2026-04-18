// 农历、节气、常见节日（1900–2100），供日历格子展示。

/// 农历日期（展示用）
class LunarDate {
  final int year;
  final int month;
  final int day;
  final bool isLeapMonth;

  const LunarDate({
    required this.year,
    required this.month,
    required this.day,
    required this.isLeapMonth,
  });
}

/// 公历某日对应的农历文案、节气名、节日名
final class CalendarAlmanac {
  CalendarAlmanac._();

  static LunarDate solarToLunar(DateTime date) => _Lunar.solarToLunar(date);

  static String lunarTextForSolar(DateTime date) =>
      _Lunar.lunarText(solarToLunar(date));

  static String? solarTermName(DateTime date) => _SolarTerm.termNameOfDay(date);

  static String? holidayName(DateTime solarDay, LunarDate lunar) =>
      _Holiday.nameOfDay(solarDay, lunar);
}

// --- 以下为原实现，保持算法与数据不变 ---

class _Lunar {
  static const List<int> _lunarInfo = <int>[
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0,
    0x09ad0, 0x055d2, 0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540,
    0x0d6a0, 0x0ada2, 0x095b0, 0x14977, 0x04970, 0x0a4b0, 0x0b4b5, 0x06a50,
    0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970, 0x06566, 0x0d4a0,
    0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2,
    0x0a950, 0x0b557, 0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5d0, 0x14573,
    0x052d0, 0x0a9a8, 0x0e950, 0x06aa0, 0x0aea6, 0x0ab50, 0x04b60, 0x0aae4,
    0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0, 0x096d0, 0x04dd5,
    0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b5a0, 0x195a6,
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46,
    0x0ab60, 0x09570, 0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58,
    0x05ac0, 0x0ab60, 0x096d5, 0x092e0, 0x0c960, 0x0d954, 0x0d4a0, 0x0da50,
    0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5, 0x0a950, 0x0b4a0,
    0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260,
    0x0ea65, 0x0d530, 0x05aa0, 0x076a3, 0x096d0, 0x04bd7, 0x04ad0, 0x0a4d0,
    0x1d0b6, 0x0d250, 0x0d520, 0x0dd45, 0x0b5a0, 0x056d0, 0x055b2, 0x049b0,
    0x0a577, 0x0a4d0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
  ];

  static int _leapMonth(int year) => _lunarInfo[year - 1900] & 0xf;

  static int _leapDays(int year) {
    final lm = _leapMonth(year);
    if (lm == 0) return 0;
    return ((_lunarInfo[year - 1900] & 0x10000) != 0) ? 30 : 29;
  }

  static int _monthDays(int year, int month) {
    return ((_lunarInfo[year - 1900] & (0x10000 >> month)) != 0) ? 30 : 29;
  }

  static int _yearDays(int year) {
    int sum = 348;
    final info = _lunarInfo[year - 1900];
    for (int i = 0x8000; i > 0x8; i >>= 1) {
      if ((info & i) != 0) sum += 1;
    }
    return sum + _leapDays(year);
  }

  static LunarDate solarToLunar(DateTime date) {
    final dUtc = DateTime.utc(date.year, date.month, date.day);
    final baseUtc = DateTime.utc(1900, 1, 31);
    int offset = dUtc.difference(baseUtc).inDays;

    int year = 1900;
    int temp = 0;
    while (year < 2101 && offset > 0) {
      temp = _yearDays(year);
      if (offset < temp) break;
      offset -= temp;
      year++;
    }
    if (offset < 0) {
      offset += temp;
      year--;
    }

    final leap = _leapMonth(year);
    bool isLeap = false;
    int month = 1;

    while (month <= 12 && offset > 0) {
      if (leap > 0 && month == leap + 1 && !isLeap) {
        month--;
        isLeap = true;
        temp = _leapDays(year);
      } else {
        temp = _monthDays(year, month);
      }

      offset -= temp;

      if (isLeap && month == leap + 1) {
        isLeap = false;
      }

      month++;
    }

    if (offset == 0 && leap > 0 && month == leap + 1) {
      if (isLeap) {
        isLeap = false;
      } else {
        isLeap = true;
        month--;
      }
    }

    if (offset < 0) {
      offset += temp;
      month--;
    }

    final lunarMonth = month;
    final lunarDay = offset + 1;

    return LunarDate(
      year: year,
      month: lunarMonth,
      day: lunarDay,
      isLeapMonth: isLeap,
    );
  }

  static String lunarText(LunarDate lunar) {
    if (lunar.day == 1) {
      final mName = _monthName(lunar.month);
      return lunar.isLeapMonth ? '闰$mName' : mName;
    }
    return _dayName(lunar.day);
  }

  static String _monthName(int m) {
    const names = <String>[
      '正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊',
    ];
    if (m < 1 || m > 12) return '';
    return '${names[m - 1]}月';
  }

  static String _dayName(int d) {
    const tens = <String>['初', '十', '廿', '三'];
    const ones = <String>[
      '', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
    ];
    if (d == 10) return '初十';
    if (d == 20) return '二十';
    if (d == 30) return '三十';
    final ten = d ~/ 10;
    final one = d % 10;
    return '${tens[ten]}${ones[one]}';
  }
}

class _SolarTerm {
  static const List<String> _names = <String>[
    '小寒', '大寒', '立春', '雨水', '惊蛰', '春分', '清明', '谷雨', '立夏', '小满',
    '芒种', '夏至', '小暑', '大暑', '立秋', '处暑', '白露', '秋分', '寒露', '霜降',
    '立冬', '小雪', '大雪', '冬至',
  ];

  static const List<int> _sTermInfo = <int>[
    0, 21208, 42467, 63836, 85337, 107014, 128867, 150921, 173149, 195551,
    218072, 240693, 263343, 285989, 308563, 331033, 353350, 375494, 397447,
    419210, 440795, 462224, 483532, 504758,
  ];

  static String? termNameOfDay(DateTime date) {
    final y = date.year;
    if (y < 1900 || y > 2100) return null;
    final m = date.month;
    final idx1 = (m - 1) * 2;
    final idx2 = idx1 + 1;
    final dUtc = DateTime.utc(date.year, date.month, date.day);
    final term1Day = _termDayUtc(y, idx1);
    if (dUtc.day == term1Day) return _names[idx1];
    final term2Day = _termDayUtc(y, idx2);
    if (dUtc.day == term2Day) return _names[idx2];
    return null;
  }

  static int _termDayUtc(int year, int n) {
    const baseMillis = -2208549300000;
    final double millis =
        31556925974.7 * (year - 1900) + _sTermInfo[n] * 60000.0;
    final dt = DateTime.fromMillisecondsSinceEpoch(
      (baseMillis + millis).round(),
      isUtc: true,
    );
    return dt.day;
  }
}

class _Holiday {
  static const Map<int, String> _solarFixed = <int, String>{
    101: '元旦',
    214: '情人节',
    501: '劳动节',
    601: '儿童节',
    1001: '国庆节',
    1225: '圣诞节',
  };

  static const Map<int, String> _lunarFixed = <int, String>{
    101: '春节',
    115: '元宵节',
    505: '端午节',
    707: '七夕',
    815: '中秋节',
    909: '重阳节',
    1208: '腊八节',
  };

  static String? nameOfDay(DateTime solarDay, LunarDate lunar) {
    final solarKey = solarDay.month * 100 + solarDay.day;
    final solarName = _solarFixed[solarKey];
    if (solarName != null) return solarName;

    if (lunar.isLeapMonth) return null;
    final lunarKey = lunar.month * 100 + lunar.day;
    return _lunarFixed[lunarKey];
  }
}
