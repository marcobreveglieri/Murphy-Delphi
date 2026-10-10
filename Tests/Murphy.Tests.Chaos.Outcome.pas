unit Murphy.Tests.Chaos.Outcome;

interface

uses
  DUnitX.TestFramework;

type

{ TChaosOutcomeTests }

  [TestFixture]
  TChaosOutcomeTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestOutcomeBuilderCreatesPolicy;
    [Test]
    procedure TestOutcomeBuilderRejectsInvalidRate;
    [Test]
    procedure TestInjectedOutcomeIsReturned;
    [Test]
    procedure TestNotInjectedReturnsRealResult;
    [Test]
    procedure TestNoOutcomeReturnsRealResult;
    [Test]
    procedure TestOnOutcomeInjectedReceivesOutcome;
    [Test]
    procedure TestOutcomeWithOrdinalResult;
    [Test]
    procedure TestFallbackHandlesInjectedOutcome;
  end;

implementation

uses
  System.SysUtils,
  Murphy.Chaos.Outcome,
  Murphy.Globals,
  Murphy.Policy.Fallback;

/// <summary>
///  Builds a policy that always injects an empty response. Its closure
///  lives in this routine frame, so the test closures can capture the
///  policy without creating a reference cycle.
/// </summary>
function EmptyResponseChaos: IChaosOutcomePolicy<string>;
begin
  Result := TChaosOutcomeBuilder<string>
    .InjectionRate(1.0)
    .Outcome(
      function: string
      begin
        Result := '';
      end);
end;

{ TChaosOutcomeTests }

procedure TChaosOutcomeTests.Setup;
begin
  MurphyChaosEnabled := True;
end;

procedure TChaosOutcomeTests.TearDown;
begin
  MurphyChaosEnabled := True;
end;

procedure TChaosOutcomeTests.TestOutcomeBuilderCreatesPolicy;
begin
  var LPolicy := TChaosOutcomeBuilder<string>.InjectionRate(0.1);
  Assert.IsNotNull(LPolicy);
  var LGeneratedPolicy := TChaosOutcomeBuilder<string>.InjectionRateGenerator(
    function: Double
    begin
      Result := 0.1;
    end);
  Assert.IsNotNull(LGeneratedPolicy);
end;

procedure TChaosOutcomeTests.TestOutcomeBuilderRejectsInvalidRate;
begin
  Assert.WillRaise(
    procedure
    begin
      TChaosOutcomeBuilder<string>.InjectionRate(-0.5);
    end, EArgumentOutOfRangeException
  );
end;

procedure TChaosOutcomeTests.TestInjectedOutcomeIsReturned;
begin
  var LPolicy := TChaosOutcomeBuilder<string>
    .InjectionRate(1.0)
    .Outcome(
      function: string
      begin
        Result := 'Fake';
      end);
  var LExecutedCalls := 0;
  var LResult := LPolicy.Execute(
    function: string
    begin
      Inc(LExecutedCalls);
      Result := 'Real';
    end);
  Assert.AreEqual('Fake', LResult);
  Assert.AreEqual(0, LExecutedCalls, 'The function must not run when an outcome is injected');
end;

procedure TChaosOutcomeTests.TestNotInjectedReturnsRealResult;
begin
  var LPolicy := TChaosOutcomeBuilder<string>
    .InjectionRate(0.0)
    .Outcome(
      function: string
      begin
        Result := 'Fake';
      end);
  var LExecutedCalls := 0;
  var LResult := LPolicy.Execute(
    function: string
    begin
      Inc(LExecutedCalls);
      Result := 'Real';
    end);
  Assert.AreEqual('Real', LResult);
  Assert.AreEqual(1, LExecutedCalls);
end;

procedure TChaosOutcomeTests.TestNoOutcomeReturnsRealResult;
begin
  var LPolicy := TChaosOutcomeBuilder<string>.InjectionRate(1.0);
  var LResult := LPolicy.Execute(
    function: string
    begin
      Result := 'Real';
    end);
  Assert.AreEqual('Real', LResult);
end;

procedure TChaosOutcomeTests.TestOnOutcomeInjectedReceivesOutcome;
begin
  var LInjectedOutcome := '';
  var LPolicy := TChaosOutcomeBuilder<string>
    .InjectionRate(1.0)
    .Outcome(
      function: string
      begin
        Result := 'Fake';
      end)
    .OnOutcomeInjected(
      procedure(AContext: TChaosOutcomeContext<string>)
      begin
        Assert.IsNotNull(AContext);
        LInjectedOutcome := AContext.Outcome;
      end);
  LPolicy.Execute(
    function: string
    begin
      Result := 'Real';
    end);
  Assert.AreEqual('Fake', LInjectedOutcome);
end;

procedure TChaosOutcomeTests.TestOutcomeWithOrdinalResult;
begin
  var LPolicy := TChaosOutcomeBuilder<Integer>
    .InjectionRate(1.0)
    .Outcome(
      function: Integer
      begin
        Result := -1;
      end);
  var LResult := LPolicy.Execute(
    function: Integer
    begin
      Result := 42;
    end);
  Assert.AreEqual(-1, LResult);
end;

procedure TChaosOutcomeTests.TestFallbackHandlesInjectedOutcome;
begin
  // The injected empty response fails the validation of the caller,
  // and the fallback around it serves the alternate value.
  var LChaos := EmptyResponseChaos;
  var LFallback := TFallbackBuilder<string>
    .Handle([EInvalidOpException])
    .Fallback(
      function: string
      begin
        Result := 'Cached';
      end);
  var LResult := LFallback.Execute(
    function: string
    begin
      Result := LChaos.Execute(
        function: string
        begin
          Result := 'Real';
        end);
      if Result = '' then
        raise EInvalidOpException.Create('Empty response');
    end);
  Assert.AreEqual('Cached', LResult);
end;

initialization
  TDUnitX.RegisterTestFixture(TChaosOutcomeTests);

end.
