class Scopes {
  static const usersManage = 'Users.Manage';
  static const rootsManage = 'Roots.Manage';
  static const jobsManage = 'Jobs.Manage';
  static const adminVfs = 'Admin.Vfs';
  static const adminLogs = 'Admin.Logs';
  static const adminSettings = 'Admin.Settings';
  static const messagesBroadcast = 'Messages.Broadcast';
  static const serverPower = 'Server.Power';

  static const admin = [
    usersManage,
    adminVfs,
    adminLogs,
    adminSettings,
    jobsManage,
  ];
}
