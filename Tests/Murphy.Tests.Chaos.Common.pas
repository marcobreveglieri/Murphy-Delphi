unit Murphy.Tests.Chaos.Common;

interface

uses
  DUnitX.TestFramework;

type

{ TChaosCommonTests }

  [TestFixture]
  TChaosCommonTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestDefaultInjectionRate;
    [Test]
    procedure TestRateZeroNeverInjects;
    [Test]
    procedure TestRateOneAlwaysInjects;
    [Test]
    procedure TestRateHalfInjectsAboutHalf;
    [Test]
    procedure TestInvalidRateRaises;
    [Test]
    procedure TestRandomizerBelowRateInjects;
    [Test]
    procedure TestRandomizerAboveRateDoesNotInject;
    [Test]
    procedure TestDisabledNeverInjects;
    [Test]
    procedure TestEnabledGeneratorOverridesEnabled;
    [Test]
    procedure TestInjectionRateGeneratorOverridesRate;
    [Test]
    procedure TestInjectionRateGeneratorIsClamped;
    [Test]
    procedure TestGlobalSwitchDisablesChaos;
    [Test]
    procedure TestDefaultRandomizerRange;
  end;

implementation

uses
  System.SysUtils,
  Murphy.Base.Chaos,
  Murphy.Globals,
  Murphy.Services.Randomizers;

type

{ TTestChaosPolicy }

  /// <summary>
  ///  Exposes the injection decision of the chaos base class. Declaring
  ///  it in this unit also makes the protected setters reachable here.
  /// </summary>
  TTestChaosPolicy = class(TChaosPolicy)
  public
    function Inject: Boolean;
    function CountInjections(ACalls: Integer): Integer;
  end;

function TTestChaosPolicy.Inject: Boolean;
begin
  Result := ShouldInject;
end;

function TTestChaosPolicy.CountInjections(ACalls: Integer): Integer;
begin
  Result := 0;
  for var LIndex := 1 to ACalls do
    if ShouldInject then
      Inc(Result);
end;

{ TChaosCommonTests }

procedure TChaosCommonTests.Setup;
begin
  MurphyChaosEnabled := True;
end;

procedure TChaosCommonTests.TearDown;
begin
  MurphyChaosEnabled := True;
end;

procedure TChaosCommonTests.TestDefaultInjectionRate;
begin
  // The default rate is 0.001, the same as Polly.
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetRandomizer(function: Double begin Result := 0.0005; end);
    Assert.IsTrue(LPolicy.Inject);
    LPolicy.SetRandomizer(function: Double begin Result := 0.002; end);
    Assert.IsFalse(LPolicy.Inject);
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestRateZeroNeverInjects;
begin
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetInjectionRate(0.0);
    Assert.AreEqual(0, LPolicy.CountInjections(1000));
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestRateOneAlwaysInjects;
begin
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetInjectionRate(1.0);
    Assert.AreEqual(1000, LPolicy.CountInjections(1000));
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestRateHalfInjectsAboutHalf;
begin
  // With 10000 calls the standard deviation is 50: the accepted range
  // is wide enough to never fail by chance.
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetInjectionRate(0.5);
    var LInjections := LPolicy.CountInjections(10000);
    Assert.IsTrue((LInjections > 4000) and (LInjections < 6000),
      Format('Unexpected injections: %d', [LInjections]));
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestInvalidRateRaises;
begin
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    Assert.WillRaise(
      procedure
      begin
        LPolicy.SetInjectionRate(-0.1);
      end, EArgumentOutOfRangeException
    );
    Assert.WillRaise(
      procedure
      begin
        LPolicy.SetInjectionRate(1.1);
      end, EArgumentOutOfRangeException
    );
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestRandomizerBelowRateInjects;
begin
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetInjectionRate(0.5);
    LPolicy.SetRandomizer(function: Double begin Result := 0.3; end);
    Assert.IsTrue(LPolicy.Inject);
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestRandomizerAboveRateDoesNotInject;
begin
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetInjectionRate(0.5);
    LPolicy.SetRandomizer(function: Double begin Result := 0.7; end);
    Assert.IsFalse(LPolicy.Inject);
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestDisabledNeverInjects;
begin
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetInjectionRate(1.0);
    LPolicy.SetEnabled(False);
    Assert.AreEqual(0, LPolicy.CountInjections(100));
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestEnabledGeneratorOverridesEnabled;
begin
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetInjectionRate(1.0);
    LPolicy.SetEnabled(False);
    LPolicy.SetEnabledGenerator(function: Boolean begin Result := True; end);
    Assert.IsTrue(LPolicy.Inject);
    LPolicy.SetEnabled(True);
    LPolicy.SetEnabledGenerator(function: Boolean begin Result := False; end);
    Assert.IsFalse(LPolicy.Inject);
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestInjectionRateGeneratorOverridesRate;
begin
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetInjectionRate(0.0);
    LPolicy.SetInjectionRateGenerator(function: Double begin Result := 1.0; end);
    Assert.IsTrue(LPolicy.Inject);
    LPolicy.SetInjectionRate(1.0);
    LPolicy.SetInjectionRateGenerator(function: Double begin Result := 0.0; end);
    Assert.IsFalse(LPolicy.Inject);
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestInjectionRateGeneratorIsClamped;
begin
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetInjectionRateGenerator(function: Double begin Result := 5.0; end);
    Assert.AreEqual(100, LPolicy.CountInjections(100));
    LPolicy.SetInjectionRateGenerator(function: Double begin Result := -3.0; end);
    Assert.AreEqual(0, LPolicy.CountInjections(100));
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestGlobalSwitchDisablesChaos;
begin
  var LPolicy := TTestChaosPolicy.Create([]);
  try
    LPolicy.SetInjectionRate(1.0);
    MurphyChaosEnabled := False;
    Assert.IsFalse(LPolicy.Inject);
    MurphyChaosEnabled := True;
    Assert.IsTrue(LPolicy.Inject);
  finally
    LPolicy.Free;
  end;
end;

procedure TChaosCommonTests.TestDefaultRandomizerRange;
begin
  var LMin := 1.0;
  var LMax := 0.0;
  var LSum := 0.0;
  for var LIndex := 1 to 10000 do
  begin
    var LValue := Randomizer.NextDouble;
    Assert.IsTrue((LValue >= 0.0) and (LValue < 1.0),
      Format('Value out of range: %g', [LValue]));
    if LValue < LMin then
      LMin := LValue;
    if LValue > LMax then
      LMax := LValue;
    LSum := LSum + LValue;
  end;
  // Values must spread over the whole interval around a 0.5 mean.
  Assert.IsTrue(LMin < 0.01);
  Assert.IsTrue(LMax > 0.99);
  Assert.AreEqual(0.5, LSum / 10000, 0.05);
end;

initialization
  TDUnitX.RegisterTestFixture(TChaosCommonTests);

end.
