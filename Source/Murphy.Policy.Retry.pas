unit Murphy.Policy.Retry;

interface

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Base.Policy;

type

{ TRetryContext }

  /// <summary>
  ///  Contains information about the current retry attempt
  ///  and can be used to change the policy at runtime.
  /// </summary>
  TRetryContext = class(TObject)
  private
    FAttempts: Integer;
    FException: Exception;
    FWaitDelay: TTimeSpan;
  public
    property Attempts: Integer read FAttempts;
    property Exception: Exception read FException;
    property WaitDelay: TTimeSpan read FWaitDelay write FWaitDelay;
  end;

{ IRetryPolicy }

  /// <summary>
  ///  Represents the interface of the "Retry" policy pattern.
  /// </summary>
  IRetryPolicy = interface(IPolicy)
    ['{7F6C8429-D08C-4ADF-82F6-FD96747CCA4C}']
    procedure Execute(AProc: TProc);
    function Retry(ATimes: Integer = 1): IRetryPolicy;
    function RetryForever: IRetryPolicy;
    function RetryOnce: IRetryPolicy;
    function Wait(ADelay: TTimeSpan): IRetryPolicy;
    function When(APredicate: TPredicate<TRetryContext>): IRetryPolicy;
  end;

{ TRetryPolicy }

  /// <summary>
  ///  Represents the concrete implementation of "Retry" policy pattern.
  /// </summary>
  TRetryPolicy = class(TPolicy, IRetryPolicy)
  private
    FRetryTimes: Integer;
    FWaitDelay: TTimeSpan;
    FWhenPredicate: TPredicate<TRetryContext>;
  public
    constructor Create(AExceptionTypes: TArray<ExceptClass>); override;
    procedure Execute(AProc: TProc);
    function Retry(ATimes: Integer = 1): IRetryPolicy;
    function RetryForever: IRetryPolicy;
    function RetryOnce: IRetryPolicy;
    function Wait(ADelay: TTimeSpan): IRetryPolicy;
    function When(APredicate: TPredicate<TRetryContext>): IRetryPolicy;
  end;

{ TRetryBuilder }

  /// <summary>
  ///  Represents an helper to create "Retry" policy instances.
  /// </summary>
  TRetryBuilder = class sealed (TPolicyBuilder<IRetryPolicy>)
  public
    class function Handle(AExceptionTypes: TArray<ExceptClass>): IRetryPolicy; override;
  end;

implementation

uses
  Murphy.Services.Schedulers;

{ TRetryPolicy }

constructor TRetryPolicy.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create(AExceptionTypes);
  FRetryTimes := 1;
  FWaitDelay := TTimeSpan.FromSeconds(1);
end;

procedure TRetryPolicy.Execute(AProc: TProc);
begin
  var
  LContext := TRetryContext.Create;
  try
    LContext.FWaitDelay := FWaitDelay;
    while True do
    begin
      Inc(LContext.FAttempts);
      try
        AProc;
        Break;
      except
        on E: Exception do
        begin
          if not IsHandled(E) then
            raise;
          LContext.FException := E;
          if Assigned(FWhenPredicate) and not FWhenPredicate(LContext) then
            raise;
          if (FRetryTimes >= 0) and (LContext.Attempts > FRetryTimes) then
            raise;
          // The exception object is destroyed when this handler exits,
          // so the context must not keep a reference across attempts.
          LContext.FException := nil;
          Scheduler.WaitFor(LContext.WaitDelay);
        end;
      end;
    end;
  finally
    LContext.Free;
  end;
end;

function TRetryPolicy.Retry(ATimes: Integer): IRetryPolicy;
begin
  FRetryTimes := ATimes;
  Result := Self;
end;

function TRetryPolicy.RetryForever: IRetryPolicy;
begin
  FRetryTimes := -1;
  Result := Self;
end;

function TRetryPolicy.RetryOnce: IRetryPolicy;
begin
  FRetryTimes := 1;
  Result := Self;
end;

function TRetryPolicy.Wait(ADelay: TTimeSpan): IRetryPolicy;
begin
  FWaitDelay := ADelay;
  Result := Self;
end;

function TRetryPolicy.When(APredicate: TPredicate<TRetryContext>): IRetryPolicy;
begin
  FWhenPredicate := APredicate;
  Result := Self;
end;

{ TRetryBuilder }

class function TRetryBuilder.Handle(AExceptionTypes: TArray<ExceptClass>): IRetryPolicy;
begin
  Result := TRetryPolicy.Create(AExceptionTypes);
end;

end.
