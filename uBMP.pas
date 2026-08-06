unit uBMP;
{$MODE objfpc}{$H+}
{$modeswitch advancedrecords}
{$codepage utf8} // ← これを追加！
interface
uses
   classes,SysUtils,FPImage,
   FPWritePNM,FPWritePNG,FPWriteBMP,
   FPReadPNG,FPReadJPEG,FPReadPNM,FPReadBMP;

type
   rgbColor = record
      b,g,r:word;
   end;

   BMPArray = array of word;
   BMPRecord=record
      bmpBodySize:longint;
      BMPWidth,BMPHeight:longint;

      bmpBody:BMPArray;
      procedure new(x,y:integer);
      procedure SetPixel(x,y:integer;col:rgbColor);
      
      // 自動判定用の統一書き出しメソッド
      procedure WriteFile(FN: string);
      
      // 統一読み込みメソッド
      procedure ReadFile(FN:String);
   end;

implementation

procedure BMPRecord.new(x,y:longint);
begin
   Setlength(BMPBody,x*y*3*2);
   BMPWidth:=x;BMPHeight:=y;
   bmpBodySize:=longint(x*y)*3*2;
end;

procedure BMPRecord.SetPixel(x,y:integer;col:rgbColor);
begin
   bmpBody[(y*BMPWidth+x)*3  ]:=col.b;
   bmpBody[(y*BMPWidth+x)*3+1]:=col.g;
   bmpBody[(y*BMPWidth+x)*3+2]:=col.r;
end;

// ----------------------------------------------------
// 拡張子から判別して自動で適切な出力を行うメソッド
// ----------------------------------------------------
procedure BMPRecord.WriteFile(FN: string);
var
   image:TFPMemoryImage;
   Ext: String;
   Writer: TFPCustomImageWriter;
   x,y:integer;
begin
   image := TFPMemoryImage.Create (bmpWidth,bmpHeight);
   for y:=0 to bmpHeight-1 do
      for x:=0 to bmpWidth-1 do 
         image.colors[x,bmpHeight-y-1]:=FPColor(bmpBody[(y*bmpWidth+x)*3+2],
                                                bmpBody[(y*bmpWidth+x)*3+1],
                                                bmpBody[(y*bmpWidth+x)*3  ]);
   
   Ext := LowerCase(ExtractFileExt(FN));
   Writer := nil;

   // 拡張子判定でライターを選択
   if (Ext = '.ppm') or (Ext = '.pnm') then begin
      Writer := TFPWriterPNM.Create;
      TFPWriterPNM(Writer).BinaryFormat := false;
   end
   else if Ext = '.png' then begin
      Writer := TFPWriterPNG.Create;
      TFPWriterPNG(Writer).WordSized:=false;
   end
   else if Ext = '.bmp' then
      Writer := TFPWriterBMP.Create
   else
   begin
      WriteLn('未対応の拡張子のためファイル名をout.pngに ');
      FN:='out.png';
      Writer := TFPWriterPNG.Create;
      TFPWriterPNG(Writer).WordSized:=false;
   end;

   try
      WriteLn('保存中: ', FN, ' (フォーマット: ', UpperCase(Copy(Ext, 2, Length(Ext))), ')');
      Image.SaveToFile(FN, Writer);
      WriteLn('保存が完了しました。');
   finally
      Writer.Free;
   end;
end;


procedure BMPRecord.ReadFile(FN:string);
var
   Ext:string;
   myImage: TFPMemoryImage;
   reader : TFPCustomImageReader;
   x,y:integer;
begin
   myImage := TFPMemoryImage.Create(0, 0);
   Ext := LowerCase(ExtractFileExt(FN));
   reader := nil;

   // 拡張子判定でリーダーを選択
   if Ext='.ppm' then begin
      reader:=TFPReaderPNM.Create;
   end
   else if Ext = '.png' then begin
      reader := TFPReaderPNG.Create;
   end
   else if Ext='.jpg' then begin
      reader:=TFPReaderJPEG.Create;
   end
   else if Ext = '.bmp' then
      reader := TFPReaderBMP.Create
   else
   begin
      WriteLn('未対応の拡張子のため中止 ');
      Halt(0);
   end;
   try
      myImage.LoadFromFile(FN, reader);
      new(myImage.width,myImage.height);
      for y:=0 to MyImage.Height-1 do begin
         for x:=0 to myImage.width-1 do begin
            bmpBody[(y*bmpWidth+x)*3+2]:=myImage.colors[x,bmpHeight-y-1].red;
            bmpBody[(y*bmpWidth+x)*3+1]:=myImage.colors[x,bmpHeight-y-1].Green;
            bmpBody[(y*bmpWidth+x)*3  ]:=myImage.colors[x,bmpHeight-y-1].Blue;
         end;
      end;
   except
      on E: Exception do
         WriteLn('Error loading file: ', E.Message);
   end;

   reader.Free;
   myImage.Free;
end;


begin
end.
