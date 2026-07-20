unit Murphy.Tests.Cache;

interface

uses
  DUnitX.TestFramework;

type

{ TCacheTests }

  [TestFixture]
  TCacheTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestCacheHandle;
    [Test]
    procedure TestCacheFirstCallInvokesFunc;
    [Test]
    procedure TestCacheSecondCallReturnsCachedValue;
    [Test]
    procedure TestCacheExpiredValueIsRefreshed;
    [Test]
    procedure TestCacheInvalidateForcesRefresh;
    [Test]
    procedure TestCacheServesStaleValueOnHandledException;
    [Test]
    procedure TestCacheRethrowsWhenExceptionNotHandled;
    [Test]
    procedure TestCacheRethrowsWhenCacheEmpty;
    [Test]
    procedure TestCacheWithIntegerResult;
  end;

implementation

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Globals,
  Murphy.Policy.Cache;

{ TCacheTests }

procedure TCacheTests.Setup;
begin
  // Freezes the clock: with a positive expire duration the cached
  // value never expires during tests, while a negative duration makes
  // it always expired, so both paths are testable without delays.
  MurphyTestModeEnabled := True;
end;

procedure TCacheTests.TearDown;
begin
  MurphyTestModeEnabled := False;
end;

procedure TCacheTests.TestCacheHandle;
begin
  var LPolicy := TCacheBuilder<string>
    .Handle([EFileNotFoundException])
    .Expire(TTimeSpan.FromSeconds(30));
  Assert.IsNotNull(LPolicy);
end;

procedure TCacheTests.TestCacheFirstCallInvokesFunc;
begin
  var LPolicy := TCacheBuilder<string>
    .Handle([])
    .Expire(TTimeSpan.FromSeconds(30));
  var LCallCount := 0;
  var LResult := LPolicy.Execute(
    function: string
    begin
      Inc(LCallCount);
      Result := 'value';
    end);
  Assert.AreEqual('value', LResult);
  Assert.AreEqual(1, LCallCount);
end;

procedure TCacheTests.TestCacheSecondCallReturnsCachedValue;
begin
  var LPolicy := TCacheBuilder<string>
    .Handle([])
    .Expire(TTimeSpan.FromSeconds(30));
  var LCallCount := 0;
  var LFunc: TFunc<string> :=
    function: string
    begin
      Inc(LCallCount);
      Result := 'value';
    end;
  LPolicy.Execute(LFunc);
  var LResult := LPolicy.Execute(LFunc);
  Assert.AreEqual('value', LResult);
  Assert.AreEqual(1, LCallCount);
end;

procedure TCacheTests.TestCacheExpiredValueIsRefreshed;
begin
  var LPolicy := TCacheBuilder<string>
    .Handle([])
    .Expire(TTimeSpan.FromSeconds(-1));
  var LCallCount := 0;
  var LFunc: TFunc<string> :=
    function: string
    begin
      Inc(LCallCount);
      Result := 'value ' + IntToStr(LCallCount);
    end;
  LPolicy.Execute(LFunc);
  var LResult := LPolicy.Execute(LFunc);
  Assert.AreEqual('value 2', LResult);
  Assert.AreEqual(2, LCallCount);
end;

procedure TCacheTests.TestCacheInvalidateForcesRefresh;
begin
  var LPolicy := TCacheBuilder<string>
    .Handle([])
    .Expire(TTimeSpan.FromSeconds(30));
  var LCallCount := 0;
  var LFunc: TFunc<string> :=
    function: string
    begin
      Inc(LCallCount);
      Result := 'value';
    end;
  LPolicy.Execute(LFunc);
  LPolicy.Invalidate;
  LPolicy.Execute(LFunc);
  Assert.AreEqual(2, LCallCount);
end;

procedure TCacheTests.TestCacheServesStaleValueOnHandledException;
begin
  var LPolicy := TCacheBuilder<string>
    .Handle([EFileNotFoundException])
    .Expire(TTimeSpan.FromSeconds(-1));
  LPolicy.Execute(
    function: string
    begin
      Result := 'stale value';
    end);
  var LResult := LPolicy.Execute(
    function: string
    begin
      raise EFileNotFoundException.Create('Refresh failed');
    end);
  Assert.AreEqual('stale value', LResult);
end;

procedure TCacheTests.TestCacheRethrowsWhenExceptionNotHandled;
begin
  var LPolicy := TCacheBuilder<string>
    .Handle([EFileNotFoundException])
    .Expire(TTimeSpan.FromSeconds(-1));
  LPolicy.Execute(
    function: string
    begin
      Result := 'stale value';
    end);
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        function: string
        begin
          raise EInvalidOpException.Create('Refresh failed');
        end);
    end, EInvalidOpException
  );
end;

procedure TCacheTests.TestCacheRethrowsWhenCacheEmpty;
begin
  var LPolicy := TCacheBuilder<string>
    .Handle([EFileNotFoundException])
    .Expire(TTimeSpan.FromSeconds(30));
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        function: string
        begin
          raise EFileNotFoundException.Create('Refresh failed');
        end);
    end, EFileNotFoundException
  );
end;

procedure TCacheTests.TestCacheWithIntegerResult;
begin
  var LPolicy := TCacheBuilder<Integer>
    .Handle([])
    .Expire(TTimeSpan.FromSeconds(30));
  var LCallCount := 0;
  var LFunc: TFunc<Integer> :=
    function: Integer
    begin
      Inc(LCallCount);
      Result := 42;
    end;
  LPolicy.Execute(LFunc);
  var LResult := LPolicy.Execute(LFunc);
  Assert.AreEqual(42, LResult);
  Assert.AreEqual(1, LCallCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TCacheTests);

end.
