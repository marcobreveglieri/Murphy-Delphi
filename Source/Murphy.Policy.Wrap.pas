unit Murphy.Policy.Wrap;

interface

uses
  System.SysUtils,
  Murphy.Base.Policy;

type

{ IPolicyWrap }

  /// <summary>
  ///  Represents the interface of the "Policy Wrap" pattern, that
  ///  combines multiple policies into a single one. Being itself an
  ///  executable policy, a wrap can be nested inside another wrap.
  /// </summary>
  IPolicyWrap = interface(IExecutablePolicy)
    ['{DA04B25E-C53F-4C39-BB0D-EFC7E6A5537D}']
  end;

{ TPolicyWrap }

  /// <summary>
  ///  Represents the concrete implementation of "Policy Wrap" pattern.
  /// </summary>
  TPolicyWrap = class(TPolicy, IPolicyWrap)
  private
    FPolicies: TArray<IExecutablePolicy>;
    procedure ExecuteFrom(AIndex: Integer; AProc: TProc);
  public
    constructor CreateWrap(const APolicies: TArray<IExecutablePolicy>);
    procedure Execute(AProc: TProc);
  end;

{ TPolicyWrapBuilder }

  /// <summary>
  ///  Represents an helper to create "Policy Wrap" instances. Note
  ///  that this builder does not derive from TPolicyBuilder: a wrap
  ///  has no exception filter of its own, since each wrapped policy
  ///  applies its own filter.
  /// </summary>
  TPolicyWrapBuilder = class sealed
  public
    /// <summary>
    ///  Combines the given policies outermost-first: Wrap([A, B])
    ///  executes A(B(action)).
    /// </summary>
    class function Wrap(const APolicies: TArray<IExecutablePolicy>): IPolicyWrap;
  end;

{ TPolicyWrapItem<TResult> }

  /// <summary>
  ///  Holds one policy of a generic policy wrap: either an executable
  ///  one (Retry, Timeout, Circuit Breaker...) or a function one
  ///  (Fallback, Cache, Chaos Outcome). The implicit operators let the
  ///  two kinds be mixed in the same array without any adapter.
  /// </summary>
  TPolicyWrapItem<TResult> = record
  private
    FExecutable: IExecutablePolicy;
    FFunction: IFunctionPolicy<TResult>;
  public
    class operator Implicit(const APolicy: IExecutablePolicy): TPolicyWrapItem<TResult>;
    class operator Implicit(const APolicy: IFunctionPolicy<TResult>): TPolicyWrapItem<TResult>;
    function Execute(AFunc: TFunc<TResult>): TResult;
    function IsAssigned: Boolean;
  end;

{ IPolicyWrap<TResult> }

  /// <summary>
  ///  Represents the interface of the "Policy Wrap" pattern for policies
  ///  that return a value. Being itself a function policy, it can be
  ///  nested inside another generic wrap.
  /// </summary>
  IPolicyWrap<TResult> = interface(IFunctionPolicy<TResult>)
    ['{A9E4D7B2-1C58-4E3F-8B6A-0F7D3C2E9A41}']
  end;

{ TPolicyWrap<TResult> }

  /// <summary>
  ///  Represents the concrete implementation of the generic "Policy
  ///  Wrap" pattern.
  /// </summary>
  TPolicyWrap<TResult> = class(TPolicy, IPolicyWrap<TResult>)
  private
    FPolicies: TArray<TPolicyWrapItem<TResult>>;
    function ExecuteFrom(AIndex: Integer; AFunc: TFunc<TResult>): TResult;
  public
    constructor CreateWrap(const APolicies: TArray<TPolicyWrapItem<TResult>>);
    function Execute(AFunc: TFunc<TResult>): TResult;
  end;

{ TPolicyWrapBuilder<TResult> }

  /// <summary>
  ///  Represents an helper to create generic "Policy Wrap" instances,
  ///  the ones that can include policies returning a value. It follows
  ///  the same rules of TPolicyWrapBuilder.
  /// </summary>
  TPolicyWrapBuilder<TResult> = class sealed
  public
    /// <summary>
    ///  Combines the given policies outermost-first: Wrap([A, B])
    ///  executes A(B(function)). Each one can be an executable policy
    ///  or a function policy of the same result type. An executable
    ///  policy that ends without running the function (or that is
    ///  abandoned by a timeout) yields the default value of the result.
    /// </summary>
    class function Wrap(const APolicies: TArray<TPolicyWrapItem<TResult>>): IPolicyWrap<TResult>;
  end;

implementation

uses
  Murphy.Resources.Strings;

{ TPolicyWrap }

constructor TPolicyWrap.CreateWrap(const APolicies: TArray<IExecutablePolicy>);
begin
  inherited Create([]);
  if Length(APolicies) = 0 then
    raise EArgumentException.Create(StrErrPolicyWrapNoPolicies);
  FPolicies := APolicies;
end;

procedure TPolicyWrap.Execute(AProc: TProc);
begin
  ExecuteFrom(0, AProc);
end;

procedure TPolicyWrap.ExecuteFrom(AIndex: Integer; AProc: TProc);
begin
  // Recursion (instead of a pre-composed chain of closures) keeps
  // every captured value immutable per frame, so a wrap instance can
  // be reused and executed concurrently.
  if AIndex > High(FPolicies) then
    AProc()
  else
    FPolicies[AIndex].Execute(
      procedure
      begin
        ExecuteFrom(AIndex + 1, AProc);
      end);
end;

{ TPolicyWrapBuilder }

class function TPolicyWrapBuilder.Wrap(
  const APolicies: TArray<IExecutablePolicy>): IPolicyWrap;
begin
  Result := TPolicyWrap.CreateWrap(APolicies);
end;

{ TPolicyWrapItem<TResult> }

class operator TPolicyWrapItem<TResult>.Implicit(
  const APolicy: IExecutablePolicy): TPolicyWrapItem<TResult>;
begin
  Result.FExecutable := APolicy;
  Result.FFunction := nil;
end;

class operator TPolicyWrapItem<TResult>.Implicit(
  const APolicy: IFunctionPolicy<TResult>): TPolicyWrapItem<TResult>;
begin
  Result.FExecutable := nil;
  Result.FFunction := APolicy;
end;

function TPolicyWrapItem<TResult>.Execute(AFunc: TFunc<TResult>): TResult;
begin
  if Assigned(FFunction) then
    Exit(FFunction.Execute(AFunc));
  // An executable policy runs a procedure: the value is carried out by a
  // variable local to this call. A timed-out attempt that goes on in the
  // background writes its own variable, never the one of a later attempt.
  var LResult := Default(TResult);
  FExecutable.Execute(
    procedure
    begin
      LResult := AFunc();
    end);
  Result := LResult;
end;

function TPolicyWrapItem<TResult>.IsAssigned: Boolean;
begin
  Result := Assigned(FExecutable) or Assigned(FFunction);
end;

{ TPolicyWrap<TResult> }

constructor TPolicyWrap<TResult>.CreateWrap(
  const APolicies: TArray<TPolicyWrapItem<TResult>>);
begin
  inherited Create([]);
  if Length(APolicies) = 0 then
    raise EArgumentException.Create(StrErrPolicyWrapNoPolicies);
  for var LPolicy in APolicies do
    if not LPolicy.IsAssigned then
      raise EArgumentException.Create(StrErrPolicyWrapNilPolicy);
  FPolicies := APolicies;
end;

function TPolicyWrap<TResult>.Execute(AFunc: TFunc<TResult>): TResult;
begin
  Result := ExecuteFrom(0, AFunc);
end;

function TPolicyWrap<TResult>.ExecuteFrom(AIndex: Integer;
  AFunc: TFunc<TResult>): TResult;
begin
  // Same recursion of the non-generic wrap, for the same reason: every
  // captured value is immutable per frame, so the wrap is reusable.
  if AIndex > High(FPolicies) then
    Result := AFunc()
  else
    Result := FPolicies[AIndex].Execute(
      function: TResult
      begin
        Result := ExecuteFrom(AIndex + 1, AFunc);
      end);
end;

{ TPolicyWrapBuilder<TResult> }

class function TPolicyWrapBuilder<TResult>.Wrap(
  const APolicies: TArray<TPolicyWrapItem<TResult>>): IPolicyWrap<TResult>;
begin
  Result := TPolicyWrap<TResult>.CreateWrap(APolicies);
end;

end.
