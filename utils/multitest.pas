program ExportMultiFormatExample;

{$mode objfpc}{$H+}

uses
  SysUtils,
  Classes,
  FPImage,
  // 必要な画像フォーマットのライターユニットを追加します
  FPWritePNM,   // PPM / PGM / PBM 用
  FPWritePNG,   // PNG 用
  FPWriteBMP;   // BMP 用

// ----------------------------------------------------
// メモリ上に画像を生成する関数
// ----------------------------------------------------
function CreateSampleImage(Width, Height: Integer): TFPMemoryImage;
var
  X, Y: Integer;
  Color: TFPColor;
begin
  Result := TFPMemoryImage.Create(Width, Height);
  for Y := 0 to Height - 1 do
  begin
    for X := 0 to Width - 1 do
    begin
      // TFPColor の各色は 0 〜 65535 ($FFFF) のWord範囲
      Color.Red   := Round((X / (Width - 1)) * 65535);
      Color.Green := Round((Y / (Height - 1)) * 65535);
      Color.Blue  := 32768; // 固定値（中間度合いの青）
      Color.Alpha := alphaOpaque;

      Result.Colors[X, Y] := Color;
    end;
  end;
end;

// ----------------------------------------------------
// 拡張子に応じたライターを取得して保存する手続き
// ----------------------------------------------------
procedure SaveImageToFile(Image: TFPMemoryImage; const FileName: String);
var
  Ext: String;
  Writer: TFPCustomImageWriter;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Writer := nil;

  // 拡張子判定でライターを選択
  if (Ext = '.ppm') or (Ext = '.pnm') then
    Writer := TFPWriterPNM.Create
  else if Ext = '.png' then
    Writer := TFPWriterPNG.Create
  else if Ext = '.bmp' then
    Writer := TFPWriterBMP.Create
  else
  begin
    WriteLn('エラー: 未対応の拡張子です (', Ext, ')');
    Exit;
  end;

  try
    WriteLn('保存中: ', FileName, ' (フォーマット: ', UpperCase(Copy(Ext, 2, Length(Ext))), ')');
    Image.SaveToFile(FileName, Writer);
    WriteLn('保存が完了しました。');
  finally
    Writer.Free;
  end;
end;

// ----------------------------------------------------
// メイン処理
// ----------------------------------------------------
var
  Image: TFPMemoryImage;
  TargetFileName: String;
begin
  // コマンドライン引数が指定されている場合はそれを使用し、
  // 指定がない場合はデフォルトの複数フォーマットで一括出力します。
  if ParamCount > 0 then
  begin
    TargetFileName := ParamStr(1);
    Image := CreateSampleImage(200, 200);
    try
      SaveImageToFile(Image, TargetFileName);
    finally
      Image.Free;
    end;
  end
  else
  begin
    WriteLn('引数が指定されていないため、各種フォーマットで自動出力します。');
    WriteLn('使用法: ', ExtractFileName(ParamStr(0)), ' <出力ファイル名.ppm|png|bmp>');
    WriteLn('----------------------------------------------------');

    Image := CreateSampleImage(200, 200);
    try
      // 自動的に各種フォーマットで出力
      SaveImageToFile(Image, 'output.ppm');
      SaveImageToFile(Image, 'output.png');
      SaveImageToFile(Image, 'output.bmp');
    finally
      Image.Free;
    end;
  end;
end.