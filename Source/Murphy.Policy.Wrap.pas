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

end.
