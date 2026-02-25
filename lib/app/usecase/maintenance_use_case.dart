import '../local/bookmark_repository.dart';
import '../maintenance/maintenance_service.dart';

class MaintenanceUseCase {
  MaintenanceUseCase({
    required BookmarkRepository repository,
    required MaintenanceService maintenanceService,
  })  : _repository = repository,
        _maintenanceService = maintenanceService;

  final BookmarkRepository _repository;
  final MaintenanceService _maintenanceService;

  Future<SlimDownResult> slimDown() {
    return _maintenanceService.slimDown();
  }

  Future<DedupResult> deduplicate({
    required bool removeExact,
    required bool removeSimilar,
  }) {
    return _repository.deduplicate(
      removeExact: removeExact,
      removeSimilar: removeSimilar,
    );
  }
}
