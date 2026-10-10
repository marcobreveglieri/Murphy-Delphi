# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Murphy for Delphi is a Chaos Engineering library that implements resilience patterns for Delphi applications. The library provides ready-to-use policy classes that help developers test and improve system reliability by handling failures gracefully.

**Important**: This library reached its first stable release (v1.0.0). The public API is considered stable; new patterns and improvements will follow in a backward-compatible way where possible.

## Build and Test Commands

### Running Tests
```bash
# DUnitX test framework is used
# Open and compile Tests\Murphy.Tests.dpr in Delphi IDE
# Or run from command line using MSBuild:
msbuild Tests\Murphy.Tests.dpr

# The test project uses conditional compilation:
# - {$IFDEF TESTINSIGHT}: Uses TestInsight test runner
# - {$ELSE}: Uses console logger
```

### Running Demos
```bash
# Interactive demo application showing all patterns
# Compile and run Demos\00_Primer\Murphy.Demos.Primer.dpr
msbuild Demos\00_Primer\Murphy.Demos.Primer.dpr
```

### Package Installation
```bash
# Via Blocks package manager (recommended)
blocks install marcobreveglieri.murphy-delphi

# Manual installation: Add Source\ folder to project search path
```

## Architecture

### Core Design Pattern: Policy Builder Pattern

All policies follow a consistent builder pattern with three layers:

1. **Policy Builder** (`TPolicyBuilder<TPolicy>`) - Entry point for creating policies
2. **Policy Interface** (`IPolicy`, `IRetryPolicy`, etc.) - Fluent API contract
3. **Policy Implementation** (`TPolicy`, `TRetryPolicy`, etc.) - Concrete execution logic

**Base Abstraction** (`Murphy.Base.Policy.pas`):
- `IPolicy`: Base interface with `IsHandled(Exception)` method for exception filtering
- `TPolicy`: Abstract base class managing exception type arrays (`FExceptionTypes`)
- `TPolicyBuilder<TPolicy>`: Generic builder providing `Handle()` method to specify handled exceptions

### Policy Patterns

**1. Retry Pattern** (`Murphy.Policy.Retry.pas`)
- Retries operations that fail with specified exceptions
- Configurable retry count, wait delays, and conditional retry logic
- Context object (`TRetryContext`) tracks attempts and allows runtime customization
- Usage: `TRetryBuilder.Handle([ExceptionClass]).Retry(5).Wait(delay).Execute(proc)`

**2. Circuit Breaker** (`Murphy.Policy.CircuitBreaker.pas`)
- Prevents cascading failures by opening circuit after threshold failures
- States: Closed (normal), Open (blocked), HalfOpen (testing), Isolated (manual override)
- Throws `EBrokenCircuitException` when circuit is open/isolated
- Auto-recovery after configurable duration
- Usage: `TCircuitBreakerBuilder.Handle([E]).Fail(2).Within(duration).Execute(proc)`

**3. Rate Limit** (`Murphy.Policy.RateLimit.pas`)
- Throttles execution to prevent resource exhaustion
- Token bucket algorithm using `TStack<TGUID>` for tracking available calls
- Throws `ERateLimitRejectedException` when limit exceeded
- Auto-resets after time window expires
- Usage: `TRateLimitBuilder.Handle([E]).Allow(20).Within(timespan).Execute(proc)`

**4. Fallback Pattern** (`Murphy.Policy.Fallback.pas`)
- Returns alternate value when operation fails
- Generic implementation: `IFallbackPolicy<TResult>` and `TFallbackPolicy<TResult>`
- Only policy that uses `TFunc<TResult>` instead of `TProc`
- Usage: `TFallbackBuilder<String>.Handle([E]).Fallback(fallbackFunc).Execute(func)`

### Chaos Strategies

Modeled on Polly's chaos engineering (https://www.pollydocs.org/chaos/), they inject failures on purpose to test the resilience policies.

- **Base** (`Murphy.Base.Chaos.pas`): `TChaosPolicy` (derives from `TPolicy`) holds the common options and decides via `ShouldInject`: global `MurphyChaosEnabled` switch → `Enabled`/`EnabledGenerator` → `InjectionRate`/`InjectionRateGenerator` (default 0.001, rate 0 never and 1 always) compared with the randomizer
- **Fault** (`Murphy.Chaos.Fault.pas`): raises an exception instead of the action (`EChaosFaultException` by default)
- **Latency** (`Murphy.Chaos.Latency.pas`): waits via `Scheduler.WaitFor` (skipped in test mode), then runs the action
- **Behavior** (`Murphy.Chaos.Behavior.pas`): runs custom code before the action
- **Outcome** (`Murphy.Chaos.Outcome.pas`): generic `TFunc<TResult>` policy returning a fake result; like Fallback/Cache it cannot join a `TPolicyWrap`
- Builders are sealed and do not derive from `TPolicyBuilder` (chaos does not filter exceptions): the entry point is `InjectionRate(Rate)` or `InjectionRateGenerator(Func)`
- Every interface redeclares the common fluent options (Delphi has no covariant returns); generator variants use distinct names (`...Generator`) instead of overloads, so a function is never evaluated once at configuration time by mistake
- Chaos policies go last (innermost) in a `TPolicyWrap`

### Service Abstraction Layer

**Scheduler Service** (`Murphy.Services.Schedulers.pas`):
- Abstracts time and delay operations via `IScheduler` interface
- `TConcreteScheduler`: Uses `TThread.Sleep()` and `TDateTime.Now`
- `TTestScheduler`: Mocked for testing (no sleep, fixed time)
- Controlled by global flag `MurphyTestModeEnabled` in `Murphy.Globals.pas`
- Used by Retry (delays), Circuit Breaker (time tracking), and Rate Limit (bucket expiry)

**Randomizer Service** (`Murphy.Services.Randomizers.pas`):
- `IRandomizer.NextDouble` returns values in [0, 1) for the chaos injection decision
- Shared lock-free SplitMix64 instance: thread-safe, and it does not touch the application's `RandSeed`
- Not affected by test mode: tests use rates 0/1 or a per-policy `Randomizer(Func)` for deterministic results

### Exception Handling Strategy

All policies:
1. Accept array of exception types via builder's `Handle()` method
2. Use inherited `IsHandled(Exception)` to filter exceptions
3. Only handle specified exception types, re-raising others
4. Allow chaining: exceptions not handled by policy bubble up

### Fluent Interface Pattern

All policies return `Self` (the interface) from configuration methods to enable method chaining:
```delphi
TRetryBuilder.Handle([E])
  .Retry(5)
  .Wait(TTimeSpan.FromSeconds(2))
  .Execute(proc);
```

## Project Structure

- `Source/` - Core library units
  - `Murphy.dpk` - Package definition (requires only RTL)
  - `Murphy.Base.Policy.pas` - Base policy framework
  - `Murphy.Policy.*.pas` - Individual pattern implementations
  - `Murphy.Base.Chaos.pas` - Base class of the chaos strategies
  - `Murphy.Chaos.*.pas` - Chaos strategy implementations
  - `Murphy.Services.Schedulers.pas` - Time abstraction service
  - `Murphy.Services.Randomizers.pas` - Random number service for chaos injection
  - `Murphy.Globals.pas` - Global configuration (test mode flag)
  - `Murphy.Resources.Strings.pas` - Localized error messages
- `Tests/` - DUnitX test suite
- `Demos/00_Primer/` - Interactive console demo showing all patterns

## Delphi Compatibility

- **Required**: Delphi 11 Alexandria or later
- Uses modern language features: inline variables, generics, anonymous methods
- May work on earlier versions with modifications

## Key Implementation Details

- All policies use interface reference counting (inherit from `TInterfacedObject`)
- Test mode (`MurphyTestModeEnabled`) eliminates time delays for fast unit testing
- Circuit Breaker stores last exception in `FBrokenFor` field for inner exception pattern
- Rate Limit uses GUID tokens to track available call slots
- Retry pattern allows runtime modification of wait delay via `TRetryContext.WaitDelay`
- Chaos Fault frees the generated exception when `OnFaultInjected` raises, since the fault is then never raised

## Testing Notes

- Delphi implements all the anonymous methods of a routine on one shared frame object. In a test, a closure that captures the policy variable (e.g. inside `Assert.WillRaise`) plus a closure stored in the policy (callback, generator) creates a reference cycle and a memory leak. The same happens when a captured `TProc`/`TFunc` variable holds a closure of the same routine: the frame references itself. The tests use `ExecuteCatching` from `Tests/Murphy.Tests.Helpers.pas` instead, or build the policy in a separate routine (needed for the `TFunc<TResult>` policies, which `ExecuteCatching` does not accept)
- The full suite must shut down with an empty leak report; in the console runner the built-in memory manager writes it to stderr ("Unexpected Memory Leak") after the final Enter. To narrow a leak down run a single fixture, e.g. `Murphy.Tests.exe --run:Murphy.Tests.Retry`: the report names the leaked frames as `<Fixture>.<Test>$ActRec`
