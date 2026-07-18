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
  Murphy.Policy.Retry;

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
  Assert.WillRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          var E := EFileNotFoundException.Create('Error Message');
          E.ErrorCode := 123;
          raise E;
        end);
    end, EFileNotFoundException
  );
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
  Assert.WillNotRaise(
    procedure
    begin
      LPolicy.Execute(
        procedure
        begin
          if LErrorCode > 0 then
            Exit;
          Inc(LErrorCode);
          var E := EFileNotFoundException.Create('Error Message');
          E.ErrorCode := LErrorCode;
          raise E;
        end);
    end, EFileNotFoundException
  );
end;

initialization
  TDUnitX.RegisterTestFixture(TRetryTests);

end.

