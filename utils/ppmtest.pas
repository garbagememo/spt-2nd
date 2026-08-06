program ExportPPMExample;

{$mode objfpc}{$H+}

uses
  SysUtils,
  FPImage,       // 画像の基本クラス（TFPMemoryImage, FPColorなど）
  FPWritePNM;    // PPM/PGM/PBM書き出し用のユニット

var
  Image: TFPMemoryImage;
  Writer: TFPWriterPNM;
  X, Y: Integer;
  Color: TFPColor;
begin
  WriteLn('PPM画像を生成中...');

  // 1. 100x100 ピクセルのメモリ上画像オブジェクトを作成
  Image := TFPMemoryImage.Create(100, 100);
  try
    // 2. ピクセルデータの作成（水平方向のグラデーション）
    for Y := 0 to Image.Height - 1 do
    begin
      for X := 0 to Image.Width - 1 do
      begin
        // TFPColor の各色は 0 〜 65535 ($FFFF) のWord範囲で指定します
        Color.Red   := Round((X / (Image.Width - 1)) * 65535);
        Color.Green := Round((Y / (Image.Height - 1)) * 65535);
        Color.Blue  := 32768; // 固定値（中間度合いの青）
        Color.Alpha := alphaOpaque; // 不透明

        Image.Colors[X, Y] := Color;
      end;
    end;

    // 3. ライターの初期化と設定
    Writer := TFPWriterPNM.Create;
    try
      // デフォルトでバイナリPPM（P6形式）として出力されます
      // （アスキー形式にする場合は Writer.PPMAscii := True とします）

      // 4. ファイルへ保存
      Image.SaveToFile('output.ppm', Writer);
      WriteLn('output.ppm の書き出しが完了しました！');

    finally
      Writer.Free;
    end;

  finally
    Image.Free;
  end;
end.
