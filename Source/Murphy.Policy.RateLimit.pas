unit Murphy.Policy.RateLimit;

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.TimeSpan,
  Murphy.Base.Policy;

type

{ ERateLimitRejectedException }

  /// <summary>
  ///  Exception raised at every call when rate limit has been reached.
  /// </summary>
  ERateLimitRejectedException = class(Exception)
  public
  end;

{ IRateLimitPolicy }

  /// <summary>
  ///  Represents the interface of the "Rate Limit" policy pattern.
  /// </summary>
  IRateLimitPolicy = interface(IPolicy)
    ['{B4AFFB0E-C958-4D89-A2BC-79659915581E}']
    function Allow(ACalls: Integer): IRateLimitPolicy;
    procedure Execute(AProc: TProc);
    function Within(ADuration: TTimeSpan): IRateLimitPolicy;
  end;

{ TRateLimitPolicy }

  /// <summary>
  ///  Represents the concrete implementation of "Rate Limit" policy pattern.
  /// </summary>
  TRateLimitPolicy = class(TPolicy, IRateLimitPolicy)
  private
    FAllowedCalls: Integer;
    FBucketIds: TStack<TGUID>;
    FBucketTime: TDateTime;
    FWithinDuration: TTimeSpan;
  protected
    function IsBucketExpired: Boolean;
  public
    constructor Create(AExceptionTypes: TArray<ExceptClass>); override;
    destructor Destroy; override;
    function Allow(ACalls: Integer): IRateLimitPolicy;
    procedure Execute(AProc: TProc);
    function Within(ADuration: TTimeSpan): IRateLimitPolicy;
  end;

{ TRateLimitBuilder }

  /// <summary>
  ///  Represents an helper to create "Rate Limit" policy instances.
  /// </summary>
  TRateLimitBuilder = class sealed (TPolicyBuilder<IRateLimitPolicy>)
  public
    /// <summary>
    ///  Creates a "Rate Limit" policy instance. Note that the exception
    ///  types passed here are currently not used by this policy: calls
    ///  are throttled regardless of any exception filter.
    /// </summary>
    class function Handle(AExceptionTypes: TArray<ExceptClass>): IRateLimitPolicy; override;
  end;

implementation

uses
  System.DateUtils,
  Murphy.Resources.Strings,
  Murphy.Services.Schedulers;

{ TRateLimitPolicy }

constructor TRateLimitPolicy.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create(AExceptionTypes);
  FAllowedCalls := 20;
  FBucketIds := TStack<TGUID>.Create;
  FBucketTime := MinDateTime;
  FWithinDuration := TTimeSpan.FromSeconds(1);
end;

destructor TRateLimitPolicy.Destroy;
begin
  if Assigned(FBucketIds) then
    FreeAndNil(FBucketIds);
  inherited Destroy;
end;

procedure TRateLimitPolicy.Execute(AProc: TProc);
begin
  TMonitor.Enter(Self);
  try
    if IsBucketExpired then
    begin
      FBucketIds.Clear;
      for var LBucketIndex := 1 to FAllowedCalls do
        FBucketIds.Push(TGUID.NewGuid);
      FBucketTime := Scheduler.Now;
    end;
    if FBucketIds.Count <= 0 then
      raise ERateLimitRejectedException.Create(StrErrRateLimitExceeded);
    FBucketIds.Pop;
  finally
    TMonitor.Exit(Self);
  end;
  AProc;
end;

function TRateLimitPolicy.IsBucketExpired: Boolean;
begin
  Result := (FBucketTime + FWithinDuration) < Scheduler.Now;
end;

function TRateLimitPolicy.Allow(ACalls: Integer): IRateLimitPolicy;
begin
  FAllowedCalls := ACalls;
  Result := Self;
end;

function TRateLimitPolicy.Within(ADuration: TTimeSpan): IRateLimitPolicy;
begin
  FWithinDuration := ADuration;
  Result := Self;
end;

{ TRateLimitBuilder }

class function TRateLimitBuilder.Handle(
  AExceptionTypes: TArray<ExceptClass>): IRateLimitPolicy;
begin
  Result := TRateLimitPolicy.Create(AExceptionTypes);
end;

end.
