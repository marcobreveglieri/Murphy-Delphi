unit Murphy.Base.Policy;

interface

uses
  System.SysUtils;

type

{ IPolicy }

  /// <summary>
  ///  Represents the base contract for any derived interface
  ///  that refers to a policy pattern.
  /// </summary>
  IPolicy = interface
    ['{245776D9-D6F2-4472-BD64-C08A9E41C568}']
    function IsHandled(AException: Exception): Boolean;
  end;

{ IExecutablePolicy }

  /// <summary>
  ///  Represents the contract for policies that can execute
  ///  a parameterless action. Policies implementing this interface
  ///  can participate in a policy wrap.
  /// </summary>
  IExecutablePolicy = interface(IPolicy)
    ['{79460F38-81AD-48CF-8A2A-F10028F86F1B}']
    procedure Execute(AProc: TProc);
  end;

{ TPolicy }

  /// <summary>
  ///  Represents the base class that share functionality that can be
  ///  inherited by descendant classes implementing policy patterns.
  /// </summary>
  TPolicy = class abstract (TInterfacedObject, IPolicy)
  private
    FExceptionTypes: TArray<ExceptClass>;
  public
    constructor Create(AExceptionTypes: TArray<ExceptClass>); virtual;
    function IsHandled(AException: Exception): Boolean;
  end;

{ TPolicyBuilder }

  /// <summary>
  ///  Represents the base class that share functionality
  ///  with all the policy instance builders.
  /// </summary>
  TPolicyBuilder<TPolicy: IPolicy> = class
  public
    class function Handle(AExceptionType: ExceptClass): TPolicy; overload; virtual;
    class function Handle(AExceptionTypes: TArray<ExceptClass>): TPolicy; overload; virtual; abstract;
  end;

implementation

{ TPolicy }

constructor TPolicy.Create(AExceptionTypes: TArray<ExceptClass>);
begin
  inherited Create;
  FExceptionTypes := AExceptionTypes;
end;

function TPolicy.IsHandled(AException: Exception): Boolean;
begin
  if Assigned(FExceptionTypes) then
    for var LExceptClass in FExceptionTypes do
      if AException.InheritsFrom(LExceptClass) then
      begin
        Result := True;
        Exit;
      end;
  Result := False;
end;

{ TPolicyBuilder<TPolicy> }

class function TPolicyBuilder<TPolicy>.Handle(AExceptionType: ExceptClass): TPolicy;
begin
  Result := Handle([AExceptionType]);
end;

end.
