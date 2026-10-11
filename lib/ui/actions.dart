/// Things the pages can ask the shell to do (dialogs, file dialogs, PDF export).
abstract class AppActions {
  Future<void> exportReport();
  Future<void> importData();
  Future<void> exportData();
  Future<void> printSounding();
}
