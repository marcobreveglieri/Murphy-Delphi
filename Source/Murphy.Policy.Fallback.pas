unit Murphy.Policy.Fallback;

interface

uses
  System.SysUtils,
  Murphy.Base.Policy;

type

{ IFallbackPolicy<TResult> }

  /// <summary>
  ///  Represents the interface of the "Fallback" policy pattern.
  /// </summary>
  IFallbackPolicy<TResult> = interface (IFunctionPolicy<TResult>)
    ['{FAF09E9F-03E5-4E80-B1D2-09DDFB0492A3}']
    function Fallback(AFunc: TFunc<TResult>): IFallbackPolicy<TResult>;
  end;

{ TFallbackPolicy<TResult> }

  /// <summary>
  ///  Represents the concrete implementation of "Fallback" policy pattern.
  /// </summary>
  TFallbackPolicy<TResult> = class (TPolicy, IFallbackPolicy<TResult>)
  private
    FFallbackFunc: TFunc<TResult>;
  public
    function Execute(AFunc: TFunc<TResult>): TResult;
    function Fallback(AFunc: TFunc<TResult>): IFallbackPolicy<TResult>;
  end;

{ TFallbackBuilder }

  TFallbackBuilder<TResult> = class sealed (TPolicyBuilder<IFallbackPolicy<TResult>>)
  public
    class function Handle(AExceptionTypes: TArray<ExceptClass>): IFallbackPolicy<TResult>; override;
  end;

implementation

{ TFallbackPolicy<TResult> }

function TFallbackPolicy<TResult>.Execute(AFunc: TFunc<TResult>): TResult;
begin
  try
    Result := AFunc;
  except
    on E: Exception do
    begin
      if not IsHandled(E) then
        raise;
      if not Assigned(FFallbackFunc) then
        raise;
      Result := FFallbackFunc();
    end;
  end;
end;

function TFallbackPolicy<TResult>.Fallback(AFunc: TFunc<TResult>): IFallbackPolicy<TResult>;
begin
  FFallbackFunc := AFunc;
  Result := Self;
end;

{ TFallbackBuilder<TResult> }

class function TFallbackBuilder<TResult>.Handle(
  AExceptionTypes: TArray<ExceptClass>): IFallbackPolicy<TResult>;
begin
  Result := TFallbackPolicy<TResult>.Create(AExceptionTypes);
end;

end.
