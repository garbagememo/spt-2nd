unit uObjShape;

{$MODE objfpc}{$H+}
{$INLINE ON}
{$modeswitch advancedrecords}
{$codepage utf8} // ← これを追加！

{$S+} 

interface
uses
   {$ifdef unix}
   cwstring, // ← Linux/Unix環境でUTF-8(System/WideString)を正しく扱うために必須
   {$endif}
   SysUtils, Classes, uVect, uBMP, Math, uShape;

const
   EPS2 = EPS * EPS;

type
   PolygonClass = class(ShapeClass)
      v0, v1, v2, n: Vec3;
      constructor Create(const v0_, v1_, v2_, n_: Vec3; tx_: TextureClass; m_: MaterialClass); reintroduce;
      function intersect(const r: RayRecord): InterInfo; override;
      function GetNorm(x: Vec3): Vec3; override;
      procedure dump; override;
   end;

   // Dir パラメータを追加（Dir が空文字の場合は現在のディレクトリから読み込み）
   procedure LoadObjFile(Dir, FN: string; Shapes: TList); 
   procedure SetAttribShapeList(Shapes: TList; e_, c_: Vec3; refl_: RefType);

var
   PolygonDumpFlag: boolean;

implementation

// 複数属性の管理用レコード体
type
   TMaterialRecord = record
      Name: string;
      Color: Vec3;
      Emit: Vec3;
      Refl: RefType;
      Tx: TextureClass;
      Mat: MaterialClass;
   end;

constructor PolygonClass.Create(const v0_, v1_, v2_, n_: Vec3; tx_: TextureClass; m_: MaterialClass);
var
   BoundMax, BoundMin: Vec3;
begin
  
   tx := tx_;
   m := m_;

   v0 := v0_; v1 := v1_; v2 := v2_; 
   
   // 指定された法線がゼロベクトルの場合は自動計算するフォールバック処理
   if (n_.x = 0) and (n_.y = 0) and (n_.z = 0) then
      n := ((v1 - v0) / (v2 - v0)).Norm
   else
      n := n_.Norm;

   BoundBox.new(BoundMin.new(math.min(v0.x, math.min(v1.x, v2.x)) - eps,
                             math.min(v0.y, math.min(v1.y, v2.y)) - eps,
                             math.min(v0.z, math.min(v1.z, v2.z)) - eps),
                BoundMax.new(math.max(v0.x, math.max(v1.x, v2.x)) + eps,
                             math.max(v0.y, math.max(v1.y, v2.y)) + eps,
                             math.max(v0.z, math.max(v1.z, v2.z)) + eps));
end;

function PolygonClass.intersect(const r: RayRecord): InterInfo;
var
   edge1, edge2, tvec, pvec, qvec: Vec3;
   det, inv_det, t, u, v: real;
begin
   result.t := INF;
   
   edge1 := v1 - v0; edge2 := v2 - v0;
   pvec := r.d / edge2;
   det := edge1 * pvec;
   if abs(det) < EPS2 then exit;
   inv_det := 1.0 / det;
   
   tvec := r.o - v0;
   u := tvec * pvec * inv_det;
   if (u < 0.0) or (u > 1.0) then exit;
   
   qvec := tvec / edge1;
   v := r.d * qvec * inv_det;
   if (v < 0.0) or (u + v > 1.0) then exit;
   
   t := edge2 * qvec * inv_det;
   if t > EPS then result.t := t;
end;

function PolygonClass.GetNorm(x: Vec3): Vec3;
begin
   result := n;
end;

procedure PolygonClass.dump;
begin
   write('V0='); writeVec(v0); write(' V1='); writeVec(v1); write(' v2='); writeVec(v2); write(' n='); writeVec(n);
   writeln;
end;

// ディレクトリ指定版 LoadObjFile
procedure LoadObjFile(Dir, FN: string; Shapes: TList);
  // RefType に応じた MaterialClass インスタンスを生成するヘルパー関数
  function CreateMaterialInstance(refl: RefType): MaterialClass;
  begin
     case refl of
        DIFF: Result := DiffuseClass.Create;
        SPEC: Result := MirrorClass.Create;
        REFR: Result := RefractClass.Create;
     else
        Result := DiffuseClass.Create;
     end;
  end;

  // fトークンから要素（v/vt/vn）を安全に分解抽出するヘルパー関数
  procedure ParseFaceToken(token: string; var vIdx, nIdx: Integer);
  var
     p1, p2: Integer;
     vStr, nStr: string;
  begin
     vIdx := 0; nIdx := 0;
     p1 := Pos('/', token);
     if p1 = 0 then begin
        vIdx := StrToIntDef(token, 0);
        exit;
     end;
     vStr := Copy(token, 1, p1 - 1);
     if vStr <> '' then vIdx := StrToIntDef(vStr, 0);
   
     Delete(token, 1, p1);
     p2 := Pos('/', token);
     if p2 = 0 then exit; // vnなし (v/vt のケース)
   
     // v//vn または v/vt/vn のケースにおける vn の抽出
     nStr := Copy(token, p2 + 1, MaxInt);
     if nStr <> '' then nIdx := StrToIntDef(nStr, 0);
  end;

var
   f: TextFile;
   fullPath, line, token, mtlFile, tStr: string;
   vertices: array of Vec3;
   normals: array of Vec3;
   vCount, nCount: Integer;
   x, y, z: Double;
   p1, p2, p3, n1: Integer;
   dummy, i, pIdx: Integer;
   polyN: Vec3;
   poly: PolygonClass;
   
   // 一直線判定用のベクトル変数
   v0Vec, v1Vec, v2Vec, crossV: Vec3;
   
   // 可変長面分解用の配列
   fTokens: array of string;
   fVIdx, fNIdx: array of Integer;
   fCount: Integer;

   // 複数マテリアル管理用の動的配列
   materials: array of TMaterialRecord;
   mCount: Integer;
   
   // 現在選択中のマテリアル参照用
   curTx: TextureClass;
   curMat: MaterialClass;
   
   // OBJ全体でマテリアル未指定の場合のデフォルト用
   defaultTx: TextureClass;
   defaultMat: MaterialClass;
   defColor, defEmit: Vec3;
begin
   // ディレクトリ指定がある場合は結合、無ければFNをそのまま使用
   if Dir <> '' then
      fullPath := IncludeTrailingPathDelimiter(Dir) + FN
   else
      fullPath := FN;

   writeln('Load ObjFile=', fullPath);
   if not Assigned(Shapes) then writeln('Shapes is not assigned!!');
   vCount := 0; nCount := 0; mCount := 0;
   
   // デフォルトのテクスチャ・マテリアルの準備
   defColor.New(0.8, 0.8, 0.8);
   defEmit.New(0.0, 0.0, 0.0);
   defaultTx := TextureClass.Create(defEmit, defColor);
   defaultMat := DiffuseClass.Create;
   
   curTx := defaultTx;
   curMat := defaultMat;
   
   mtlFile := ChangeFileExt(fullPath, '.mtl');
   
   // 1. MTLファイルの解析
   if FileExists(mtlFile) then begin
      AssignFile(f, mtlFile); Reset(f);
      while not Eof(f) do begin
         Readln(f, line); line := Trim(line);
         if line = '' then Continue;
         token := Copy(line, 1, Pos(' ', line + ' ') - 1);
         
         if token = 'newmtl' then begin
            Inc(mCount);
            SetLength(materials, mCount);
            materials[mCount - 1].Name := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
            // デフォルト値の割り当て（基本は乱反射・無発光）
            materials[mCount - 1].Color.New(0.8, 0.8, 0.8);
            materials[mCount - 1].Emit.New(0.0, 0.0, 0.0);
            materials[mCount - 1].Refl := DIFF;
            materials[mCount - 1].Tx := nil;
            materials[mCount - 1].Mat := nil;
         end
         else if token = 'Kd' then begin
            if mCount > 0 then begin
               line := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
               x := StrToFloat(Copy(line, 1, Pos(' ', line + ' ') - 1));
               line := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
               y := StrToFloat(Copy(line, 1, Pos(' ', line + ' ') - 1));
               z := StrToFloat(Trim(Copy(line, Pos(' ', line) + 1, MaxInt)));
               materials[mCount - 1].Color.New(x, y, z);
            end;
         end
         else if token = 'Ke' then begin // 発光色の読み込み
            if mCount > 0 then begin
               line := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
               x := StrToFloat(Copy(line, 1, Pos(' ', line + ' ') - 1));
               line := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
               y := StrToFloat(Copy(line, 1, Pos(' ', line + ' ') - 1));
               z := StrToFloat(Trim(Copy(line, Pos(' ', line) + 1, MaxInt)));
               materials[mCount - 1].Emit.New(x, y, z);
            end;
         end
         else if token = 'illum' then begin
            if mCount > 0 then begin
               dummy := StrToIntDef(Trim(Copy(line, Pos(' ', line) + 1, MaxInt)), 0);
               if dummy = 3 then
                  materials[mCount - 1].Refl := SPEC   // 鏡面反射
               else if dummy >= 4 then
                  materials[mCount - 1].Refl := REFR;  // 透明体・屈折（ガラス等）
            end;
         end
         else if token = 'Ni' then begin // 屈折率の定義があれば透明体(REFR)に設定
            if mCount > 0 then
               materials[mCount - 1].Refl := REFR;
         end;
      end;
      CloseFile(f);

      // MTLで定義された全マテリアルの TextureClass / MaterialClass インスタンスを事前に生成
      for i := 0 to mCount - 1 do begin
         materials[i].Tx := TextureClass.Create(materials[i].Emit, materials[i].Color);
         materials[i].Mat := CreateMaterialInstance(materials[i].Refl);
      end;
   end;

   if not FileExists(fullPath) then Exit;
   
   // 2. OBJファイルの解析
   AssignFile(f, fullPath); Reset(f);
   while not Eof(f) do begin
      Readln(f, line); line := Trim(line);
      if line = '' then Continue;
      token := Copy(line, 1, Pos(' ', line + ' ') - 1);
      
      // マテリアルの指定（切り替え）
      if token = 'usemtl' then begin
         token := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
         for dummy := 0 to mCount - 1 do begin
            if materials[dummy].Name = token then begin
               curTx := materials[dummy].Tx;
               curMat := materials[dummy].Mat;
               Break;
            end;
         end;
      end
      // 頂点座標の読み込み
      else if token = 'v' then begin
         line := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
         x := StrToFloat(Copy(line, 1, Pos(' ', line + ' ') - 1));
         line := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
         y := StrToFloat(Copy(line, 1, Pos(' ', line + ' ') - 1));
         z := StrToFloat(Trim(Copy(line, Pos(' ', line) + 1, MaxInt)));
         
         Inc(vCount); SetLength(vertices, vCount);
         vertices[vCount - 1].new(x, y, z);
      end
      // 法線ベクトル (vn) の読み込み対応
      else if token = 'vn' then begin
         line := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
         x := StrToFloat(Copy(line, 1, Pos(' ', line + ' ') - 1));
         line := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
         y := StrToFloat(Copy(line, 1, Pos(' ', line + ' ') - 1));
         z := StrToFloat(Trim(Copy(line, Pos(' ', line) + 1, MaxInt)));
         
         Inc(nCount); SetLength(normals, nCount);
         normals[nCount - 1].New(x, y, z);
      end
      // 面情報の読み込み（3角形・4角形・多角形対応）
      else if token = 'f' then begin
         line := Trim(Copy(line, Pos(' ', line + ' ') + 1, MaxInt));
         
         // 1. 行内の頂点要素トークンを全て分解抽出
         fCount := 0;
         SetLength(fTokens, 0);
         while line <> '' do begin
            pIdx := Pos(' ', line);
            if pIdx = 0 then begin
               tStr := line;
               line := '';
            end else begin
               tStr := Copy(line, 1, pIdx - 1);
               line := Trim(Copy(line, pIdx + 1, MaxInt));
            end;
            if tStr <> '' then begin
               Inc(fCount);
               SetLength(fTokens, fCount);
               fTokens[fCount - 1] := tStr;
            end;
         end;

         // 2. 3頂点以上ある場合、三角分割（Triangle Fan）して登録
         if fCount >= 3 then begin
            SetLength(fVIdx, fCount);
            SetLength(fNIdx, fCount);
            for i := 0 to fCount - 1 do
               ParseFaceToken(fTokens[i], fVIdx[i], fNIdx[i]);

            // 頂点 (v0, v_i, v_{i+1}) で三角形を構築
            for i := 1 to fCount - 2 do begin
               p1 := fVIdx[0];
               p2 := fVIdx[i];
               p3 := fVIdx[i + 1];

               // 面法線の選択（有効な法線インデックスが存在すれば割り当て）
               n1 := fNIdx[0];
               if (n1 > 0) and (n1 <= nCount) then
                  polyN := normals[n1 - 1]
               else if (fNIdx[i] > 0) and (fNIdx[i] <= nCount) then
                  polyN := normals[fNIdx[i] - 1]
               else
                  polyN.New(0, 0, 0);

               // インデックスが範囲内であることを確認してPolygonを追加
               if (p1 > 0) and (p1 <= vCount) and
                  (p2 > 0) and (p2 <= vCount) and
                  (p3 > 0) and (p3 <= vCount) then begin
                  
                  v0Vec := vertices[p1 - 1];
                  v1Vec := vertices[p2 - 1];
                  v2Vec := vertices[p3 - 1];

                  // 2つのエッジベクトルの外積（/ 演算子）を計算
                  crossV := (v1Vec - v0Vec) / (v2Vec - v0Vec);

                  // 外積ベクトルの長さの2乗（内積 * 演算子）が EPS2 より大きい（退化三角形でない）場合のみ追加
                  if (crossV * crossV) > EPS2 then begin
                     poly := PolygonClass.Create(v0Vec, v1Vec, v2Vec, polyN, curTx, curMat);
                     Shapes.Add(poly);
                     if PolygonDumpFlag then poly.dump;
                  end;
               end;
            end;
         end;
      end;
   end;
   CloseFile(f);
   Writeln(Format('Loaded OBJ: %d vertices, %d normals.', [vCount, nCount]));
end;

procedure SetAttribShapeList(Shapes: TList; e_, c_: Vec3; refl_: RefType);
var
   i: integer;
begin
   for i := 0 to Shapes.count - 1 do begin
      ShapeClass(Shapes[i]).SetAttrib(e_, c_, refl_);
   end;
end;

begin
   PolygonDumpFlag := false;
end.
