unit Murphy.Tests.Retry;

interface

uses
  DUnitX.TestFramework;

type

{ TRetryTests }

  [TestFixture]
  TRetryTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TestRetryHandle;
    [Test]
    procedure TestRetryHandleWithRetries;
    [Test]
    procedure TestRetryHandleWhenConditionThrowsException;
    [Test]
    procedure TestRetryHandleWhenConditionSkipsException;
  end;

implementation

uses
  System.SysUtils,
  Murphy.Globals,
  Murphy.Policy.Retry,
  Murphy.Tests.Helpers;

{ TRetryTests }

procedure TRetryTests.Setup;
begin
  // Skips the real wait delays between retry attempts.
  MurphyTestModeEnabled := True;
end;

procedure TRetryTests.TearDown;
begin
  MurphyTestModeEnabled := False;
end;

procedure TRetryTests.TestRetryHandle;
begin
  var LPolicy := TRetryBuilder
    .Handle(EFileNotFoundException);
  Assert.IsNotNull(LPolicy);
end;

procedure TRetryTests.TestRetryHandleWithRetries;
begin
  var LPolicy := TRetryBuilder
    .Handle(EFileNotFoundException)
    .Retry(3);
  Assert.IsNotNull(LPolicy);
end;

procedure TRetryTests.TestRetryHandleWhenConditionThrowsException;
const
  ErrorCode = 123;
begin
  var LPolicy := TRetryBuilder.Handle(EFileNotFoundException)
    .When(
      function (C: TRetryContext): Boolean
      begin
        Result := EFileNotFoundException(C.Exception).ErrorCode <> ErrorCode;
      end
    );
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      var E := EFileNotFoundException.Create('Error Message');
      E.ErrorCode := 123;
      raise E;
    end);
  Assert.AreEqual('EFileNotFoundException', LFailure.ClassName);
end;

procedure TRetryTests.TestRetryHandleWhenConditionSkipsException;
begin
  var LErrorCode := 0;
  var LPolicy := TRetryBuilder.Handle(EFileNotFoundException)
    .When(
      function (C: TRetryContext): Boolean
      begin
        Result := EFileNotFoundException(C.Exception).ErrorCode = LErrorCode;
      end
    );
  var LFailure := ExecuteCatching(LPolicy,
    procedure
    begin
      if LErrorCode > 0 then
        Exit;
      Inc(LErrorCode);
      var E := EFileNotFoundException.Create('Error Message');
      E.ErrorCode := LErrorCode;
      raise E;
    end);
  Assert.IsFalse(LFailure.Raised);
end;

initialization
  TDUnitX.RegisterTestFixture(TRetryTests);

end.

