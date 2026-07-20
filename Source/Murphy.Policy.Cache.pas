unit Murphy.Policy.Cache;

interface

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Base.Policy;

type

{ ICachePolicy<TResult> }

  /// <summary>
  ///  Represents the interface of the "Cache" policy pattern.
  ///  Each policy instance caches a single value: create one policy
  ///  for every operation whose result must be cached. When the cached
  ///  value has expired, the operation runs again to refresh it; if the
  ///  refresh raises a handled exception and a previously cached value
  ///  exists (even an expired one), that stale value is returned as the
  ///  last known good result.
  /// </summary>
  ICachePolicy<TResult> = interface(IPolicy)
    ['{4988F6C2-CB95-466E-8F6B-2BCFE8776014}']
    function Execute(AFunc: TFunc<TResult>): TResult;
    function Expire(ADuration: TTimeSpan): ICachePolicy<TResult>;
    procedure Invalidate;
  end;

{ TCachePolicy<TResult> }

  /// <summary>
  ///  Represents the concrete implementation of "Cache" policy pattern.
  ///  When TResult is a class type the policy does not own the cached
  ///  instances: prefer interfaces or records for cached data.
  /// </summary>
  TCachePolicy<TResult> = class(TPolicy, ICachePolicy<TResult>)
  private
    FCachedAt: TDateTime;
    FCachedValue: TResult;
    FExpireDuration: TTimeSpan;
    FHasValue: Boolean;
  protected
    function IsExpired: Boolean;
  public
    constructor Create(AExceptionTypes: TArray<ExceptClass>); override;
    function Execute(AFunc: TFunc<TResult>): TResult;
    function Expire(ADuration: TTimeSpan): ICachePolicy<TResult>;
    procedure Invalidate;
  end;

{ TCacheBuilder<TResult> }

  /// <summary>
  ///  Represents an helper to create "Cache" policy instances.
  /// </summary>
  TCacheBuilder<TResult> = class sealed (TPolicyBuilder<ICachePolicy<TResult>>)
  public
    /// <summary>
    ///  Creates a "Cache" policy instance. The exception types passed
    ///  here select which refresh failures may be answered with the
    ///  stale cached value: on a handled exception the last cached
    ///  value (if any) is returned; any other exception is re-raised.
    /// </summary>
    class function Handle(AExceptionTypes: TArray<ExceptClass>): ICachePolicy<TResult>; override;
  end;

implementation

uses
  System.DateUtils,
  Murphy.Services.Schedulers;

{ TCachePolicy<TResult> }

constructor TCachePolicy<TResult>.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create(AExceptionTypes);
  FCachedAt := MinDateTime;
  FExpireDuration := TTimeSpan.FromMinutes(5);
end;

function TCachePolicy<TResult>.IsExpired: Boolean;
begin
  Result := (FCachedAt + FExpireDuration) < Scheduler.Now;
end;

function TCachePolicy<TResult>.Execute(AFunc: TFunc<TResult>): TResult;
begin
  // Serves the cached value when present and still fresh.
  TMonitor.Enter(Self);
  try
    if FHasValue and not IsExpired then
      Exit(FCachedValue);
  finally
    TMonitor.Exit(Self);
  end;

  // Cache miss or expired value: refreshes outside the lock. Note
  // that concurrent misses may each invoke the function; the last
  // completed call wins the cache slot.
  try
    Result := AFunc();
  except
    on E: Exception do
    begin
      if not IsHandled(E) then
        raise;
      // Serves the stale value (expired values are deliberately
      // kept) as the last known good result; when the cache is
      // empty there is nothing to serve, so the failure surfaces.
      var LHasValue: Boolean;
      var LCachedValue: TResult;
      TMonitor.Enter(Self);
      try
        LHasValue := FHasValue;
        LCachedValue := FCachedValue;
      finally
        TMonitor.Exit(Self);
      end;
      if not LHasValue then
        raise;
      Exit(LCachedValue);
    end;
  end;

  // Stores the fresh value with its timestamp.
  TMonitor.Enter(Self);
  try
    FCachedValue := Result;
    FCachedAt := Scheduler.Now;
    FHasValue := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TCachePolicy<TResult>.Expire(ADuration: TTimeSpan): ICachePolicy<TResult>;
begin
  FExpireDuration := ADuration;
  Result := Self;
end;

procedure TCachePolicy<TResult>.Invalidate;
begin
  TMonitor.Enter(Self);
  try
    FCachedValue := Default(TResult);
    FCachedAt := MinDateTime;
    FHasValue := False;
  finally
    TMonitor.Exit(Self);
  end;
end;

{ TCacheBuilder<TResult> }

class function TCacheBuilder<TResult>.Handle(
  AExceptionTypes: TArray<ExceptClass>): ICachePolicy<TResult>;
begin
  Result := TCachePolicy<TResult>.Create(AExceptionTypes);
end;

end.
