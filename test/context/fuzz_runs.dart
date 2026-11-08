// Number of property-test iterations: TURF_FUZZ_RUNS from the environment on
// the VM (e.g. `TURF_FUZZ_RUNS=10000 dart test ...`), [defaultRuns]
// otherwise.
import 'fuzz_runs_stub.dart' if (dart.library.io) 'fuzz_runs_io.dart';

int fuzzRuns([int defaultRuns = 200]) =>
    int.tryParse(environmentValue('TURF_FUZZ_RUNS') ?? '') ?? defaultRuns;
