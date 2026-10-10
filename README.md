<div>
  <img alt="Murphy Library for Delphi" width="100%" src="./Assets/logo-murphy.png">
</div>
<br />

# Murphy for Delphi

[![Release](https://img.shields.io/github/v/release/marcobreveglieri/murphy-delphi?label=release&color=2ea44f)](https://github.com/marcobreveglieri/murphy-delphi/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Delphi](https://img.shields.io/badge/Delphi-11%2B-E62431)](https://www.embarcadero.com/products/delphi)
[![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android%20%7C%20iOS-informational)]()

**Murphy for Delphi** is a Chaos Engineering library that implements resilience and fault-tolerance patterns for Delphi applications, together with chaos strategies that inject failures on purpose to prove those patterns work. Named after Murphy's Law ("Anything that can go wrong will go wrong"), it helps you build systems that gracefully handle failures like network timeouts, service outages, and resource exhaustion.

> **ℹ️ Stable Release**
> Murphy for Delphi 1.0.0 is the first stable release. The public API is considered stable; new patterns and improvements will follow in a backward-compatible way where possible.

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
- **🐒 Chaos Strategies** - Inject faults, latency, custom behaviors and fake outcomes to verify your resilience strategies
- **🔗 Fluent API** - Intuitive, chainable builder pattern for easy configuration
- **💪 Type-Safe** - Leverages Delphi generics for compile-time type safety
- **🎭 Exception Filtering** - Handle only specific exception types
- **🧪 Testable** - Built-in test mode eliminates delays for fast unit testing
- **🔄 Composable** - Combine multiple patterns for sophisticated resilience strategies
- **📦 Zero Dependencies** - Only requires Delphi RTL

## Installation

### Using Blocks Package Manager (Recommended)

```bash
blocks install marcobreveglieri.murphy-delphi
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

## Chaos Engineering

Resilience patterns are only as good as the failures they have been tested against. Murphy includes four chaos strategies, modeled on [Polly's chaos engineering](https://www.pollydocs.org/chaos/), that inject failures on purpose in a configurable fraction of executions:

| Strategy | Unit | What it injects |
|---|---|---|
| Fault | `Murphy.Chaos.Fault` | Raises an exception instead of running the action |
| Latency | `Murphy.Chaos.Latency` | Waits before running the action |
| Behavior | `Murphy.Chaos.Behavior` | Runs custom code (e.g. dropping a connection) before the action |
| Outcome | `Murphy.Chaos.Outcome` | Returns a fake result instead of running the function |

```pascal
uses Murphy.Chaos.Fault, Murphy.Chaos.Latency, Murphy.Policy.Retry, Murphy.Policy.Wrap;

var
  Policy: IPolicyWrap;
begin
  Policy := TPolicyWrapBuilder.Wrap([
    TRetryBuilder
      .Handle(ENetworkError)
      .Retry(3),                         // The resilience under test...
    TChaosFaultBuilder
      .InjectionRate(0.1)                // ...10% of the calls fail
      .Fault(ENetworkError, 'Injected connection reset'),
    TChaosLatencyBuilder
      .InjectionRate(0.2)                // ...20% of the calls are slow
      .Latency(TTimeSpan.FromSeconds(2))
  ]);

  Policy.Execute(procedure begin CallExternalService; end);
end;
```

Every chaos policy shares the same options:

- `InjectionRate(Rate)` / `InjectionRateGenerator(Func)` - fraction of the executions affected, from 0 to 1 (default 0.001); the generator runs at every execution and wins over the fixed value
- `Enabled(Value)` / `EnabledGenerator(Func)` - turns the policy on or off, e.g. only for test users or environments
- `Randomizer(Func)` - replaces the random generator, for deterministic tests
- `OnFaultInjected`, `OnLatencyInjected`, `OnBehaviorInjected`, `OnOutcomeInjected` - callbacks to log what has been injected

Guidelines:

- **Place chaos policies last** (innermost) in a policy wrap, so the resilience policies around them react to the injected failures
- **Control the blast radius**: set the `MurphyChaosEnabled` flag (`Murphy.Globals`) to `False` to turn off every chaos policy at once, e.g. in production builds, and use `EnabledGenerator` to limit chaos to selected users or environments
- **Use Fault for exceptions** and Outcome for fake results; being generic on the result type like Fallback and Cache, Outcome does not join a policy wrap: call it inside the function executed by the other policies
- Latency waits through the scheduler service, so test mode (`MurphyTestModeEnabled`) skips the delay

**Use cases**: Testing retries, timeouts, circuit breakers and fallbacks against realistic failures, game days, resilience regression tests

**Demos**: the Chaos menu (`X`) of the [demo application](Demos/00_Primer) runs one scenario for each strategy: fault and latency against a retry, latency against a timeout, a simulated outage against a circuit breaker, fake responses against a fallback, and a dropped connection limited to a test user. The [DelphiMVCFramework demo](Demos/01_DMVC) brings chaos to a web application: a middleware injects faults and latency into the requests marked by a header, the client of a dependency injects them inside its resilience policies, and a live dashboard changes the settings at runtime and shows how the application reacts.

## Quick Start

1. **Install Murphy** using Blocks or manually
2. **Add the unit** to your uses clause: `Murphy.Policy.Retry`
3. **Create a policy** using the builder pattern
4. **Execute your code** within the policy

See the [Getting Started Guide](https://github.com/marcobreveglieri/murphy-delphi/wiki/02-Getting-Started) for detailed examples and the [Demo Application](Demos/00_Primer) for interactive examples of all patterns.

## Documentation

Comprehensive documentation is available in the [Wiki section](https://github.com/marcobreveglieri/murphy-delphi/wiki).

## Demo Application

Explore the demo in `Demos/00_Primer/Murphy.Demos.Primer.dpr` to see the patterns in action with some examples.

To see chaos engineering in a web application, run `Demos/01_DMVC/Murphy.Demos.DMVC.dpr`: it requires [DelphiMVCFramework](https://github.com/danieleteti/delphimvcframework), and its [README](Demos/01_DMVC/README.md) and [testing guide](Demos/01_DMVC/TESTING.md) explain how to build it and how to try every feature.

## License

Murphy for Delphi is released under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please see the [Contributing Guide](https://github.com/marcobreveglieri/murphy-delphi/wiki/Advanced/Contributing) for details.

## Support & Resources

- **GitHub Repository**: [marcobreveglieri/murphy-delphi](https://github.com/marcobreveglieri/murphy-delphi)
- **Issues & Bug Reports**: [GitHub Issues](https://github.com/marcobreveglieri/murphy-delphi/issues)
- **Chaos Engineering Principles**: [principlesofchaos.org](https://principlesofchaos.org/)

---

> [!IMPORTANT]
>
> Some of this documentation was generated or reworked with an LLM tool (Claude). It may therefore contain errors and/or inaccuracies. If you encounter any, please report the issue or propose a fix by submitting a pull request.
