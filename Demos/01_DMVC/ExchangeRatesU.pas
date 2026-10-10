unit ExchangeRatesU;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  Murphy.Policy.CircuitBreaker,
  Murphy.Policy.Retry,
  Murphy.Policy.Timeout;

type

{ EExchangeRatesException }

  /// <summary>
  ///  Exception raised when the exchange rates service cannot be reached.
  /// </summary>
  EExchangeRatesException = class(Exception);

{ TExchangeRateSource }

  TExchangeRateSource = (
    /// <summary>
    ///  Received from the service.
    /// </summary>
    Live,
    /// <summary>
    ///  The last rate received, served by the fallback.
    /// </summary>
    Cache
  );

{ TExchangeRate }

  TExchangeRate = record
    Rate: Double;
    Source: TExchangeRateSource;
    Attempts: Integer;
    CircuitState: TCircuitState;
  end;

{ TExchangeRatesClient }

  /// <summary>
  ///  Represents the client of a remote service that publishes the exchange
  ///  rates of the euro, simulated in process. The resilience policies
  ///  protect every call, and the chaos of the "rates" target is injected
  ///  innermost, where a real network failure would happen.
  /// </summary>
  TExchangeRatesClient = class
  private
    FBreaker: ICircuitBreakerPolicy;
    FLastRates: TDictionary<string, Double>;
    FRetry: IRetryPolicy;
    FTimeout: ITimeoutPolicy;
    function FetchRate(const ACurrency: string): Double;
    function GetLastRate(const ACurrency: string): Double;
    procedure SetLastRate(const ACurrency: string; ARate: Double);
  public
    const
      TargetName = 'rates';
    constructor Create;
    destructor Destroy; override;
    function GetRate(const ACurrency: string): TExchangeRate;
    function IsSupported(const ACurrency: string): Boolean;
  end;

/// <summary>
///  Returns the client shared by all the requests, so that its circuit
///  breaker sees the failures of every call.
/// </summary>
function ExchangeRates: TExchangeRatesClient;

implementation

uses
  System.Classes,
  System.TimeSpan,
  MVCFramework.Logger,
  Murphy.Chaos.Fault,
  Murphy.Chaos.Latency,
  Murphy.Policy.Fallback,
  Murphy.Policy.Wrap,
  Murphy.Services.Randomizers,
  ChaosSettingsU;

type
  TRemoteRate = record
    Currency: string;
    Rate: Double;
  end;

const
  RemoteRates: array[0..3] of TRemoteRate = (
    (Currency: 'USD'; Rate: 1.0842),
    (Currency: 'GBP'; Rate: 0.8571),
    (Currency: 'CHF'; Rate: 0.9468),
    (Currency: 'JPY'; Rate: 162.37)
  );

var
  GExchangeRates: TExchangeRatesClient;

function ExchangeRates: TExchangeRatesClient;
begin
  Result := GExchangeRates;
end;

function CallRemoteService(const ACurrency: string): Double;
begin
  // The real service, simulated: a fast network and rates that move a bit.
  // It is not a method, since an attempt abandoned by the timeout can
  // still call it while the application shuts down.
  TThread.Sleep(30 + Round(Randomizer.NextDouble * 70));
  for var LRemoteRate in RemoteRates do
    if LRemoteRate.Currency = ACurrency then
      Exit(LRemoteRate.Rate * (1.0 + (Randomizer.NextDouble - 0.5) / 250.0));
  raise EArgumentException.CreateFmt('Unknown currency "%s"', [ACurrency]);
end;

{ TExchangeRatesClient }

constructor TExchangeRatesClient.Create;
begin
  inherited Create;

  // The rates served by the fallback: the last ones received, starting
  // from the rates published the day before.
  FLastRates := TDictionary<string, Double>.Create;
  for var LRemoteRate in RemoteRates do
    FLastRates.Add(LRemoteRate.Currency, LRemoteRate.Rate);

  // These policies are created once and shared by all the requests: the
  // circuit breaker must count the failures of every call, while retry
  // and timeout keep no state between calls.
  FBreaker := TCircuitBreakerBuilder
    .Handle([EExchangeRatesException, ETimeoutRejectedException])
    .Fail(3)
    .Within(TTimeSpan.FromSeconds(5));
  FRetry := TRetryBuilder
    .Handle([EExchangeRatesException, ETimeoutRejectedException])
    .Retry(2)
    .Wait(TTimeSpan.FromMilliseconds(200));
  FTimeout := TTimeoutBuilder
    .Handle([])
    .After(TTimeSpan.FromSeconds(1))
    .OnTimeout(
      procedure(AContext: TTimeoutContext)
      begin
        LogW(Format('Exchange rates: attempt abandoned after %.0f ms',
          [AContext.TimeoutDuration.TotalMilliseconds]));
      end);
end;

destructor TExchangeRatesClient.Destroy;
begin
  FLastRates.Free;
  inherited Destroy;
end;

function TExchangeRatesClient.FetchRate(const ACurrency: string): Double;
begin
  // The chaos policies are created at every attempt, on the thread that
  // serves the request, where they read the blast radius; then the
  // timeout runs them on a pool thread. The fault simulates a dropped
  // connection, the latency a slow network that the timeout cuts short.
  var LPolicy := TPolicyWrapBuilder.Wrap([
    FBreaker,
    FTimeout,
    ChaosSettings.CreateFault(TargetName)
      .Fault(EExchangeRatesException, 'Connection reset by the exchange rates service')
      .OnFaultInjected(
        procedure(AFault: TChaosFaultContext)
        begin
          LogW('Chaos: fault injected into the exchange rates service');
        end),
    ChaosSettings.CreateLatency(TargetName)
      .OnLatencyInjected(
        procedure(ALatency: TChaosLatencyContext)
        begin
          LogW(Format('Chaos: %.0f ms of latency injected into the exchange rates service',
            [ALatency.Latency.TotalMilliseconds]));
        end)
  ]);

  // A variable of this attempt: an attempt abandoned by the timeout goes
  // on in background, and it must not overwrite the rate of the next one.
  var LRate: Double := 0.0;
  LPolicy.Execute(
    procedure
    begin
      LRate := CallRemoteService(ACurrency);
    end);
  Result := LRate;
end;

function TExchangeRatesClient.GetLastRate(const ACurrency: string): Double;
begin
  TMonitor.Enter(FLastRates);
  try
    Result := FLastRates[ACurrency];
  finally
    TMonitor.Exit(FLastRates);
  end;
end;

function TExchangeRatesClient.GetRate(const ACurrency: string): TExchangeRate;
begin
  var LAttempts := 0;
  var LLiveRate: Double := 0.0;
  var LSource := TExchangeRateSource.Live;

  // The fallback is created for every call, since it serves the rate of
  // this currency. It handles the open circuit too, which is not retried.
  Result.Rate := TFallbackBuilder<Double>
    .Handle([EExchangeRatesException, ETimeoutRejectedException, EBrokenCircuitException])
    .Fallback(
      function: Double
      begin
        LSource := TExchangeRateSource.Cache;
        Result := GetLastRate(ACurrency);
        LogW(Format('Exchange rates: last %s rate served by the fallback', [ACurrency]));
      end)
    .Execute(
      function: Double
      begin
        FRetry.Execute(
          procedure
          begin
            Inc(LAttempts);
            LLiveRate := FetchRate(ACurrency);
          end);
        SetLastRate(ACurrency, LLiveRate);
        Result := LLiveRate;
      end);

  Result.Source := LSource;
  Result.Attempts := LAttempts;
  Result.CircuitState := FBreaker.CircuitState;
end;

function TExchangeRatesClient.IsSupported(const ACurrency: string): Boolean;
begin
  TMonitor.Enter(FLastRates);
  try
    Result := FLastRates.ContainsKey(ACurrency);
  finally
    TMonitor.Exit(FLastRates);
  end;
end;

procedure TExchangeRatesClient.SetLastRate(const ACurrency: string; ARate: Double);
begin
  TMonitor.Enter(FLastRates);
  try
    FLastRates[ACurrency] := ARate;
  finally
    TMonitor.Exit(FLastRates);
  end;
end;

initialization

  GExchangeRates := TExchangeRatesClient.Create;

finalization

  GExchangeRates.Free;

end.
