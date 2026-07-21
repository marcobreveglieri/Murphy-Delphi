# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Murphy for Delphi is a Chaos Engineering library that implements resilience patterns for Delphi applications. The library provides ready-to-use policy classes that help developers test and improve system reliability by handling failures gracefully.

**Important**: This library is in early development (v0.1.0) and under heavy refactoring. Expect substantial changes.

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

### Service Abstraction Layer

**Scheduler Service** (`Murphy.Services.Schedulers.pas`):
- Abstracts time and delay operations via `IScheduler` interface
- `TConcreteScheduler`: Uses `TThread.Sleep()` and `TDateTime.Now`
- `TTestScheduler`: Mocked for testing (no sleep, fixed time)
- Controlled by global flag `MurphyTestModeEnabled` in `Murphy.Globals.pas`
- Used by Retry (delays), Circuit Breaker (time tracking), and Rate Limit (bucket expiry)

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
  - `Murphy.Services.Schedulers.pas` - Time abstraction service
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
