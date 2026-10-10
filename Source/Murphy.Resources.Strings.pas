unit Murphy.Resources.Strings;

interface

{ Resource strings }

resourcestring
  StrErrBulkheadRejected = 'Bulkhead limit reached: execution rejected';
  StrErrChaosFaultInjected = 'Fault injected by chaos policy';
  StrErrChaosInvalidInjectionRate = 'Chaos injection rate must be between 0 and 1';
  StrErrCircuitBroken = 'Circuit is open or isolated and is not allowing calls';
  StrErrHedgingInvalidAttempts = 'Hedging attempts count must be zero or greater';
  StrErrPolicyWrapNoPolicies = 'Policy wrap requires at least one policy';
  StrErrRateLimitExceeded = 'Rate limit exceeded: retry later';
  StrErrTimeoutExceeded = 'Operation exceeded the timeout duration';

implementation

end.
