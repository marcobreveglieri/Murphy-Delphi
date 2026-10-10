unit Murphy.Tests.Fallback;

interface

uses
  DUnitX.TestFramework;

type

{ TFallbackTests }

  [TestFixture]
  TFallbackTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestFallbackHandle;
    [Test]
    procedure TestFallbackWithFallbackFunction;
    [Test]
    procedure TestFallbackExecutesSuccessfully;
    [Test]
    procedure TestFallbackExecutesWhenExceptionHandled;
    [Test]
    procedure TestFallbackRethrowsWhenExceptionNotHandled;
    [Test]
    procedure TestFallbackRethrowsWhenNoFallbackProvided;
    [Test]
    procedure TestFallbackWithMultipleExceptionTypes;
    [Test]
    procedure TestFallbackWithFunctionResult;
  end;

implementation

uses
  System.SysUtils,
  Murphy.Policy.Fallback;

/// <summary>
///  Builds a policy that handles EFileNotFoundException with a constant
///  fallback. Its closure lives in this routine frame, so the test
///  closures can capture the policy without creating a reference cycle.
/// </summary>
function FileNotFoundFallback: IFallbackPolicy<string>;
begin
  Result := TFallbackBuilder<string>
    .Handle([EFileNotFoundException])
    .Fallback(function: string begin Result := 'fallback'; end);
end;

{ TFallbackTests }

procedure TFallbackTests.Setup;
begin
end;

procedure TFallbackTests.TearDown;
begin
end;

procedure TFallbackTests.TestFallbackHandle;
begin
  var LPolicy := TFallbackBuilder<string>
    .Handle([EFileNotFoundException]);
  Assert.IsNotNull(LPolicy);
end;

procedure TFallbackTests.TestFallbackWithFallbackFunction;
begin
  var LPolicy := TFallbackBuilder<string>
    .Handle([EFileNotFoundException])
    .Fallback(function: string begin Result := 'fallback'; end);
  Assert.IsNotNull(LPolicy);
end;

procedure TFallbackTests.TestFallbackExecutesSuccessfully;
begin
  const ExpectedResult = 'success';
  var LPolicy := TFallbackBuilder<string>
    .Handle([EFileNotFoundException])
    .Fallback(function: string begin Result := 'fallback'; end);
  
  var LResult := LPolicy.Execute(function: string begin Result := ExpectedResult; end);
  
  Assert.AreEqual(ExpectedResult, LResult);
end;

procedure TFallbackTests.TestFallbackExecutesWhenExceptionHandled;
begin
  const FallbackResult = 'fallback executed';
  var LPolicy := TFallbackBuilder<string>
    .Handle([EFileNotFoundException])
    .Fallback(function: string begin Result := FallbackResult; end);
  
  var LResult := LPolicy.Execute(
    function: string
    begin
      raise EFileNotFoundException.Create('File not found');
    end);
  
  Assert.AreEqual(FallbackResult, LResult);
end;

procedure TFallbackTests.TestFallbackRethrowsWhenExceptionNotHandled;
begin
  var LPolicy := FileNotFoundFallback;

  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        function: string
        begin
          raise EInvalidOpException.Create('Invalid operation');
        end);
    end, EInvalidOpException
  );
end;

procedure TFallbackTests.TestFallbackRethrowsWhenNoFallbackProvided;
begin
  var LPolicy := TFallbackBuilder<string>
    .Handle([EFileNotFoundException]);
  
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        function: string
        begin
          raise EFileNotFoundException.Create('File not found');
        end);
    end, EFileNotFoundException
  );
end;

procedure TFallbackTests.TestFallbackWithMultipleExceptionTypes;
begin
  const FallbackResult = 'fallback for multiple exceptions';
  var LPolicy := TFallbackBuilder<string>
    .Handle([EFileNotFoundException, EInvalidOpException])
    .Fallback(function: string begin Result := FallbackResult; end);
  
  // Test first exception type
  var LResult1 := LPolicy.Execute(
    function: string
    begin
      raise EFileNotFoundException.Create('File not found');
    end);
  Assert.AreEqual(FallbackResult, LResult1);
  
  // Test second exception type
  var LResult2 := LPolicy.Execute(
    function: string
    begin
      raise EInvalidOpException.Create('Invalid operation');
    end);
  Assert.AreEqual(FallbackResult, LResult2);
end;

procedure TFallbackTests.TestFallbackWithFunctionResult;
begin
  var LPolicy := TFallbackBuilder<Integer>
    .Handle([EDivByZero])
    .Fallback(function: Integer begin Result := -1; end);
  
  var LResult := LPolicy.Execute(
    function: Integer
    var
      Zero: Integer;
    begin
      Zero := 0;
      Result := 10 div Zero; // This will raise EDivByZero
    end);
  
  Assert.AreEqual(-1, LResult);
end;

initialization
  TDUnitX.RegisterTestFixture(TFallbackTests);

end.