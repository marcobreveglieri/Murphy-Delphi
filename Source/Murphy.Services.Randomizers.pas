unit Murphy.Services.Randomizers;

interface

type

{ IRandomizer }

  IRandomizer = interface
    ['{FD3A097A-61EB-4CD9-9A3D-574014C35B1F}']
    /// <summary>
    ///  Returns a random value greater than or equal to 0 and less than 1.
    /// </summary>
    function NextDouble: Double;
  end;

{ Routines }

  function Randomizer: IRandomizer;

implementation

uses
  System.Diagnostics,
  System.SyncObjs;

type

{ TConcreteRandomizer }

  /// <summary>
  ///  Represents a concrete implementation of randomizer service, based
  ///  on the SplitMix64 generator. It does not use System.Random, so the
  ///  RandSeed sequence of the application is left untouched, and it is
  ///  lock-free and thread-safe: the state advances atomically and the
  ///  output is a pure function of the state.
  /// </summary>
  TConcreteRandomizer = class (TInterfacedObject, IRandomizer)
  private
    FState: Int64;
  public
    constructor Create;
    function NextDouble: Double;
  end;

{ TConcreteRandomizer }

constructor TConcreteRandomizer.Create;
begin
  inherited Create;
  FState := TStopwatch.GetTimeStamp;
end;

// The generator relies on the wrap-around of 64-bit arithmetic.
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

function TConcreteRandomizer.NextDouble: Double;
const
  GoldenGamma = Int64($9E3779B97F4A7C15);
  TwoPower53 = 9007199254740992.0;
begin
  var LValue := UInt64(TInterlocked.Add(FState, GoldenGamma));
  LValue := (LValue xor (LValue shr 30)) * UInt64($BF58476D1CE4E5B9);
  LValue := (LValue xor (LValue shr 27)) * UInt64($94D049BB133111EB);
  LValue := LValue xor (LValue shr 31);
  // The 53 most significant bits fill the Double mantissa exactly.
  Result := Int64(LValue shr 11) / TwoPower53;
end;

var
  GRandomizer: IRandomizer;

{ Routines }

function Randomizer: IRandomizer;
begin
  Result := GRandomizer;
end;

initialization

  GRandomizer := TConcreteRandomizer.Create;

end.
