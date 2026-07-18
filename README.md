<div>
  <img alt="Murphy Library for Delphi" width="100%" src="./Assets/logo-murphy.png">
</div>
<br />

# Murphy for Delphi

**Murphy for Delphi** is a Chaos Engineering library that implements resilience and fault-tolerance patterns for Delphi applications. Named after Murphy's Law ("Anything that can go wrong will go wrong"), it helps you build systems that gracefully handle failures like network timeouts, service outages, and resource exhaustion.

> **⚠️ Early Development Notice**
> This library is in early development (v0.1.0) and under active refactoring. Expect substantial changes in upcoming releases.

## Why Murphy?

Modern applications face inevitable failures: network issues, service unavailability, resource limits, and external dependencies going down. Murphy provides battle-tested patterns to handle these scenarios without writing complex error-handling code from scratch.

```pascal
// Automatic retry with configurable delays - just a few lines of code!
var
  RetryPolicy: IRetryPolicy;
begin
  RetryPolicy := TRetryBuilder
    .Handle([EIdHTTPProtocolException, EIdSocketError])
    .Retry(3)
    .Wait(TTimeSpan.FromSeconds(2));

  RetryPolicy.Execute(
    procedure
    begin
      // Your code here - automatically retried on failure
      HTTP.Get('https://api.example.com/data');
    end);
end;
```

## Key Features

- **🎯 Ready-to-Use Patterns** - Retry, Circuit Breaker, Fallback, Rate Limit, Timeout, Bulkhead, Cache, Hedging, and Policy Wrap implementations
- **🔗 Fluent API** - Intuitive, chainable builder pattern for easy configuration
- **💪 Type-Safe** - Leverages Delphi generics for compile-time type safety
- **🎭 Exception Filtering** - Handle only specific exception types
- **🧪 Testable** - Built-in test mode eliminates delays for fast unit testing
- **🔄 Composable** - Combine multiple patterns for sophisticated resilience strategies
- **📦 Zero Dependencies** - Only requires Delphi RTL

## Installation

### Using Boss Package Manager (Recommended)

```bash
boss install marcobreveglieri/murphy-delphi
```

### Manual Installation

1. Download or clone the repository from GitHub
2. Add `murphy-delphi/Source` to your project's search path:
   - **Project > Options > Delphi Compiler > Search path**
   - Or add to IDE's global library path: **Tools > Options > Language > Delphi > Library**

## Patterns

Murphy implements nine essential resilience patterns:

### Retry Pattern

Automatically retries failed operations with configurable delays - perfect for transient failures.

```pascal
uses Murphy.Policy.Retry;

var
  Policy: IRetryPolicy;
begin
  Policy := TRetryBuilder
    .Handle(EDatabaseError)
    .Retry(3)
    .Wait(TTimeSpan.FromSeconds(1));

  Policy.Execute(procedure begin Database.Connect; end);
end;
```

**Use cases**: Network requests, database connections, temporary service unavailability

### Circuit Breaker Pattern

Prevents cascading failures by blocking calls to failing services temporarily.

```pascal
uses Murphy.Policy.CircuitBreaker;

var
  Policy: ICircuitBreakerPolicy;
begin
  Policy := TCircuitBreakerBuilder
    .Handle(Exception)
    .Fail(5)                             // Open after 5 failures
    .Within(TTimeSpan.FromSeconds(30));  // Auto-close after 30s

  Policy.Execute(procedure begin CallExternalService; end);
end;
```

**Use cases**: External API calls, protecting downstream services, fast-fail scenarios

### Fallback Pattern

Provides alternative results when operations fail - return cached data or defaults.

```pascal
uses Murphy.Policy.Fallback;

var
  Policy: IFallbackPolicy<string>;
  Value: string;
begin
  Policy := TFallbackBuilder<string>
    .Handle(Exception)
    .Fallback(function: string
              begin
                Result := GetCachedData; // Return fallback value
              end);

  Value := Policy.Execute(function: string
                          begin
                            Result := FetchFromAPI;
                          end);
end;
```

**Use cases**: API with fallback to cache, default values, degraded functionality

### Rate Limit Pattern

Controls operation rate to prevent resource exhaustion and API throttling.

```pascal
uses Murphy.Policy.RateLimit;

var
  Policy: IRateLimitPolicy;
begin
  Policy := TRateLimitBuilder
    .Handle([])
    .Allow(100)                          // 100 calls
    .Within(TTimeSpan.FromMinutes(1));   // Per minute

  Policy.Execute(procedure begin MakeAPICall; end);
end;
```

**Use cases**: API rate limiting, resource protection, preventing system overload

### Timeout Pattern

Aborts operations that take too long, so a hung dependency cannot hang your application.

```pascal
uses Murphy.Policy.Timeout;

var
  Policy: ITimeoutPolicy;
begin
  Policy := TTimeoutBuilder
    .Handle([])
    .After(TTimeSpan.FromSeconds(5))     // Abort after 5 seconds
    .OnTimeout(procedure(AContext: TTimeoutContext)
               begin
                 Log('Timed out after ' + AContext.ElapsedTime.ToString);
               end);

  Policy.Execute(procedure begin CallSlowService; end);
end;
```

**Use cases**: Slow network calls, unresponsive services, enforcing SLAs

### Bulkhead Pattern

Limits the number of concurrent executions to isolate resources and prevent one workload from exhausting the whole system. When the bulkhead is full, calls are rejected immediately with `EBulkheadRejectedException`.

```pascal
uses Murphy.Policy.Bulkhead;

var
  Policy: IBulkheadPolicy;
begin
  Policy := TBulkheadBuilder
    .Handle([])
    .Limit(10);                          // Max 10 concurrent executions

  Policy.Execute(procedure begin ProcessRequest; end);
end;
```

**Use cases**: Protecting connection pools, isolating workloads, capping parallel work

### Cache Pattern

Caches the result of an expensive operation for a configurable duration. Each policy instance caches a single value; if a refresh fails with a handled exception, the last known good value is returned.

```pascal
uses Murphy.Policy.Cache;

var
  Policy: ICachePolicy<string>;
  Value: string;
begin
  Policy := TCacheBuilder<string>
    .Handle(ENetworkError)               // Serve stale value on this failure
    .Expire(TTimeSpan.FromMinutes(5));   // Refresh every 5 minutes

  Value := Policy.Execute(function: string
                          begin
                            Result := FetchExpensiveData;
                          end);
end;
```

**Use cases**: Expensive lookups, remote configuration, reducing load on backends

### Hedging Pattern

Launches parallel attempts when the primary one is too slow or fails, returning the first successful result. Hedged actions should be idempotent, because losing attempts keep running in background.

```pascal
uses Murphy.Policy.Hedging;

var
  Policy: IHedgingPolicy;
begin
  Policy := THedgingBuilder
    .Handle(ENetworkError)
    .MaxAttempts(2)                      // Up to 2 extra parallel attempts
    .Delay(TTimeSpan.FromMilliseconds(500)); // Hedge after 500 ms

  Policy.Execute(procedure begin CallReplicatedService; end);
end;
```

**Use cases**: Tail-latency reduction, calling replicated services, flaky endpoints

### Policy Wrap

Combines multiple policies into a single one, applied outermost-first: `Wrap([A, B])` executes `A(B(action))`.

```pascal
uses Murphy.Policy.Retry, Murphy.Policy.Timeout, Murphy.Policy.Wrap;

var
  Policy: IPolicyWrap;
begin
  Policy := TPolicyWrapBuilder.Wrap([
    TRetryBuilder
      .Handle(ETimeoutRejectedException)
      .Retry(3),                         // Retry timed out attempts...
    TTimeoutBuilder
      .Handle([])
      .After(TTimeSpan.FromSeconds(1))   // ...each with its own timeout
  ]);

  Policy.Execute(procedure begin CallExternalService; end);
end;
```

**Use cases**: Sophisticated resilience strategies, combining retry/timeout/circuit breaker

## Quick Start

1. **Install Murphy** using Boss or manually
2. **Add the unit** to your uses clause: `Murphy.Policy.Retry`
3. **Create a policy** using the builder pattern
4. **Execute your code** within the policy

See the [Getting Started Guide](Docs/02-Getting-Started.md) for detailed examples and the [Demo Application](Demos/00_Primer) for interactive examples of all patterns.

## Documentation

Comprehensive documentation is available in the [Wiki section](https://github.com/marcobreveglieri/murphy-delphi/wiki).

## Demo Application

Explore the demo in `Demos/00_Primer/Murphy.Demos.Primer.dpr` to see the patterns in action with some examples.

## License

Murphy for Delphi is released under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please see the [Contributing Guide](Docs/Advanced/Contributing.md) for details.

## Support & Resources

- **GitHub Repository**: [marcobreveglieri/murphy-delphi](https://github.com/marcobreveglieri/murphy-delphi)
- **Issues & Bug Reports**: [GitHub Issues](https://github.com/marcobreveglieri/murphy-delphi/issues)
- **Chaos Engineering Principles**: [principlesofchaos.org](https://principlesofchaos.org/)

---

> [!IMPORTANT]
>
> Some of this documentation was generated or reworked with an LLM tool (Claude). It may therefore contain errors and/or inaccuracies. If you encounter any, please report the issue or propose a fix by submitting a pull request.
