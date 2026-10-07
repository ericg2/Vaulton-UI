class Scopes {
  static const usersManage = 'Users.Manage';
  static const rootsManage = 'Roots.Manage';
  static const jobsManage = 'Jobs.Manage';
  static const adminVfs = 'Admin.Vfs';
  static const adminLogs = 'Admin.Logs';
  static const messagesBroadcast = 'Messages.Broadcast';
  static const systemSettings = 'System.Settings';

  static const admin = [usersManage, adminVfs, adminLogs, jobsManage];
}
