const double seawaterDensity = 1.025; // t/m3 - density the hydrostatic tables are based on
const double defaultArrivalDensity = 1.022;
const double cuftToM3 = 0.028317;
const double saggingCoeff = 0.25;
const String appVersion = '5.0.1';

/// Survey cards by stage.
const Map<String, String> surveyIds = {
  'initial': 'survey-0',
  'int1': 'survey-1',
  'int2': 'survey-2',
  'final': 'survey-3',
};

/// Vendor contact details (single source, same as contact.js).
const String contactWebsite = 'https://ds.dingzihao.cn';
const String contactWebsiteLabel = 'dingzihao.cn';
const String contactWechat = 'dingzihao_cn';
const String contactEmail = '123@dingzihao.cn';

/// Licence server; override at build time: --dart-define=DS_LICENSE_URL=https://license.example.com
const String licenseServerUrl =
    String.fromEnvironment('DS_LICENSE_URL', defaultValue: 'https://license.example.com');
