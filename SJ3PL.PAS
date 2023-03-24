unit sj3pl;

interface { -------------------------------------------------------------- }

uses SJ3Graph,
     SDLPort,
     fphttpclient, opensslsockets;

procedure ResultsMenu;
function GetResults: string;

implementation { ********************************************************* }

procedure ResultsMenu;
var Results: string;
    ch1, ch2: char;
begin
    Results := GetResults;
    SJ3Graph.WriteFont(11,20,Results);
    DrawScreen;
    SDLPort.WaitForKeyPress(ch1, ch2);
end;

function GetResults: string;
var URL: string;
begin
    URL := 'https://sj3.pl/wyniki/SJ3_wyniki/ps%201314/01_klingenthal.txt';
    GetResults := TFPHttpClient.SimpleGet(URL);
end;

end.
