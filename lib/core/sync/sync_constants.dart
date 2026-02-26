abstract final class SyncConstants {
  // Frontground sync throttle window: no more than once per 120s.
  static const int throttleSeconds = 120;

  // Jianguoyun request limits in 30 minutes.
  static const int freePlanWindowLimit = 600;
  static const int paidPlanWindowLimit = 1500;
  static const int requestWindowMinutes = 30;
  static const int directoryListMaxItems = 750;

  // Single sync loop work budget.
  static const int defaultChangeBudgetPerSync = 20;
  static const int defaultRemoteBatchSize = 20;

  // Retry backoff for 429/5xx.
  static const List<int> retryBackoffMinutes = <int>[2, 4, 8, 16, 32];
}
