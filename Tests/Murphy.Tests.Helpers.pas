unit Murphy.Tests.Helpers;

interface

uses
  System.SysUtils,
  Murphy.Base.Policy;

type

{ TExecutionFailure }

  /// <summary>
  ///  Describes the exception raised by an execution, if any.
  /// </summary>
  TExecutionFailure = record
    ClassName: string;
    Message: string;
    function Raised: Boolean;
  end;

{ Routines }

  /// <summary>
  ///  Executes the action through the policy and reports the exception
  ///  raised, if any. Tests use it instead of Assert.WillRaise because a
  ///  closure capturing the policy would share the frame object with the
  ///  closures stored inside the policy, creating a reference cycle.
  /// </summary>
  function ExecuteCatching(const APolicy: IExecutablePolicy;
    const AProc: TProc): TExecutionFailure;

  /// <summary>
  ///  Returns a randomizer that yields the given values in order, then
  ///  keeps yielding the last one.
  /// </summary>
  function SequenceRandomizer(const AValues: TArray<Double>): TFunc<Double>;

implementation

{ TExecutionFailure }

function TExecutionFailure.Raised: Boolean;
begin
  Result := ClassName <> '';
end;

{ Routines }

function ExecuteCatching(const APolicy: IExecutablePolicy;
  const AProc: TProc): TExecutionFailure;
begin
  Result := Default(TExecutionFailure);
  try
    APolicy.Execute(AProc);
  except
    on E: Exception do
    begin
      Result.ClassName := E.ClassName;
      Result.Message := E.Message;
    end;
  end;
end;

function SequenceRandomizer(const AValues: TArray<Double>): TFunc<Double>;
begin
  var LIndex := 0;
  Result :=
    function: Double
    begin
      Result := AValues[LIndex];
      if LIndex < High(AValues) then
        Inc(LIndex);
    end;
end;

end.
