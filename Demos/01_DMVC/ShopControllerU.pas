unit ShopControllerU;

interface

uses
  JsonDataObjects,
  MVCFramework,
  MVCFramework.Commons;

type

{ TShopController }

  [MVCPath('/api')]
  TShopController = class(TMVCController)
  public
    /// <summary>
    ///  Served from memory: only the chaos of the incoming requests
    ///  reaches it.
    /// </summary>
    [MVCPath('/products')]
    [MVCHTTPMethod([httpGET])]
    function GetProducts: TJsonArray;

    /// <summary>
    ///  Converts the price with the exchange rates service: the chaos of
    ///  the "rates" target reaches it too, and the answer tells how the
    ///  resilience policies obtained the rate.
    /// </summary>
    [MVCPath('/products/($id)/price/($currency)')]
    [MVCHTTPMethod([httpGET])]
    function GetPrice(const id: Integer; const currency: string): TJsonObject;
  end;

implementation

uses
  System.Math,
  System.Rtti,
  System.SysUtils,
  Murphy.Policy.CircuitBreaker,
  ExchangeRatesU;

type
  TProduct = record
    Id: Integer;
    Name: string;
    PriceEur: Double;
  end;

const
  Products: array[0..3] of TProduct = (
    (Id: 1; Name: 'Murphy''s law mug'; PriceEur: 12.90),
    (Id: 2; Name: 'Chaos monkey plush'; PriceEur: 24.50),
    (Id: 3; Name: 'Circuit breaker T-shirt'; PriceEur: 19.90),
    (Id: 4; Name: 'Retry sticker pack'; PriceEur: 4.99)
  );

  RateSourceNames: array[TExchangeRateSource] of string = ('live', 'cache');

function FindProduct(AId: Integer): TProduct;
begin
  for var LProduct in Products do
    if LProduct.Id = AId then
      Exit(LProduct);
  raise EMVCException.CreateFmt(HTTP_STATUS.NotFound, 'Product %d not found', [AId]);
end;

{ TShopController }

function TShopController.GetPrice(const id: Integer; const currency: string): TJsonObject;
begin
  var LProduct := FindProduct(id);
  var LCurrency := currency.ToUpper;
  if not ExchangeRates.IsSupported(LCurrency) then
    raise EMVCException.CreateFmt(HTTP_STATUS.NotFound, 'Currency %s not supported', [currency]);

  var LRate := ExchangeRates.GetRate(LCurrency);

  Result := TJsonObject.Create;
  Result.I['productId'] := LProduct.Id;
  Result.S['product'] := LProduct.Name;
  Result.F['priceEur'] := LProduct.PriceEur;
  Result.S['currency'] := LCurrency;
  Result.F['rate'] := RoundTo(LRate.Rate, -4);
  Result.F['price'] := RoundTo(LProduct.PriceEur * LRate.Rate, -2);
  Result.S['rateSource'] := RateSourceNames[LRate.Source];
  Result.I['attempts'] := LRate.Attempts;
  Result.S['circuit'] := TRttiEnumerationType.GetName<TCircuitState>(LRate.CircuitState);
end;

function TShopController.GetProducts: TJsonArray;
begin
  Result := TJsonArray.Create;
  for var LProduct in Products do
  begin
    var LItem := Result.AddObject;
    LItem.I['id'] := LProduct.Id;
    LItem.S['name'] := LProduct.Name;
    LItem.F['priceEur'] := LProduct.PriceEur;
  end;
end;

end.
