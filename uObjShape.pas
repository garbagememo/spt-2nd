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
   
// 動的配列用の型を定義
   TMaterialArray = array of TMaterialRecord;   

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

{ ============================================================================
  プライベート・ヘルパー関数群
  ============================================================================ }

// RefType に応じた MaterialClass インスタンスを生成
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

// トークン文字列から 3 つの数値を取得して Vec3 を構築する汎用関数
function ParseVec3(line: string): Vec3;
var
   x, y, z: Double;
   rest: string;
begin
   rest := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
   x := StrToFloat(Copy(rest, 1, Pos(' ', rest + ' ') - 1));
   rest := Trim(Copy(rest, Pos(' ', rest) + 1, MaxInt));
   y := StrToFloat(Copy(rest, 1, Pos(' ', rest + ' ') - 1));
   z := StrToFloat(Trim(Copy(rest, Pos(' ', rest) + 1, MaxInt)));
   Result.New(x, y, z);
end;

// fトークンから要素（v/vt/vn）を安全に分解抽出
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
 
   nStr := Copy(token, p2 + 1, MaxInt);
   if nStr <> '' then nIdx := StrToIntDef(nStr, 0);
end;

// 面（f）行を分解して三角形ポリゴン（PolygonClass）を生成・追加する処理
procedure ProcessFaceLine(line: string; const vertices, normals: array of Vec3;
  curTx: TextureClass; curMat: MaterialClass; Shapes: TList);
var
   fCount, i, pIdx: Integer;
   tStr: string;
   fTokens: array of string;
   fVIdx, fNIdx: array of Integer;
   p1, p2, p3, n1: Integer;
   polyN, v0Vec, v1Vec, v2Vec, crossV: Vec3;
   poly: PolygonClass;
begin
   line := Trim(Copy(line, Pos(' ', line + ' ') + 1, MaxInt));
   
   // 行内の頂点要素トークンを抽出
   fCount := 0;
   while line <> '' do begin
      pIdx := Pos(' ', line);
      if pIdx = 0 then begin
         tStr := line; line := '';
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

   if fCount < 3 then Exit;

   SetLength(fVIdx, fCount);
   SetLength(fNIdx, fCount);
   for i := 0 to fCount - 1 do
      ParseFaceToken(fTokens[i], fVIdx[i], fNIdx[i]);

   // 三角分割（Triangle Fan）して登録
   for i := 1 to fCount - 2 do begin
      p1 := fVIdx[0]; p2 := fVIdx[i]; p3 := fVIdx[i + 1];

      // 面法線の選択
      n1 := fNIdx[0];
      if (n1 > 0) and (n1 <= High(normals) + 1) then
         polyN := normals[n1 - 1]
      else if (fNIdx[i] > 0) and (fNIdx[i] <= High(normals) + 1) then
         polyN := normals[fNIdx[i] - 1]
      else
         polyN.New(0, 0, 0);

      if (p1 > 0) and (p1 <= High(vertices) + 1) and
         (p2 > 0) and (p2 <= High(vertices) + 1) and
         (p3 > 0) and (p3 <= High(vertices) + 1) then begin
         
         v0Vec := vertices[p1 - 1];
         v1Vec := vertices[p2 - 1];
         v2Vec := vertices[p3 - 1];

         crossV := (v1Vec - v0Vec) / (v2Vec - v0Vec);

         // 退化三角形でない場合のみ追加
         if (crossV * crossV) > EPS2 then begin
            poly := PolygonClass.Create(v0Vec, v1Vec, v2Vec, polyN, curTx, curMat);
            Shapes.Add(poly);
            if PolygonDumpFlag then poly.dump;
         end;
      end;
   end;
end;

// MTLファイルのロード処理
procedure LoadMtlFile(const Dir, MtlFileName: string; var materials: TMaterialArray; var mCount: Integer);
var
   fMtl: TextFile;
   fullMtlPath, line, token: string;
   prevMCount, dummy, i: Integer;
begin
   if Dir <> '' then
      fullMtlPath := IncludeTrailingPathDelimiter(Dir) + MtlFileName
   else
      fullMtlPath := MtlFileName;

   if not FileExists(fullMtlPath) then Exit;

   prevMCount := mCount;
   AssignFile(fMtl, fullMtlPath); Reset(fMtl);
   while not Eof(fMtl) do begin
      Readln(fMtl, line); line := Trim(line);
      if line = '' then Continue;
      token := Copy(line, 1, Pos(' ', line + ' ') - 1);
      
      if token = 'newmtl' then begin
         Inc(mCount);
         SetLength(materials, mCount);
         materials[mCount - 1].Name := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
         materials[mCount - 1].Color.New(0.8, 0.8, 0.8);
         materials[mCount - 1].Emit.New(0.0, 0.0, 0.0);
         materials[mCount - 1].Refl := DIFF;
         materials[mCount - 1].Tx := nil;
         materials[mCount - 1].Mat := nil;
      end
      else if token = 'Kd' then begin
         if mCount > 0 then materials[mCount - 1].Color := ParseVec3(line);
      end
      else if token = 'Ke' then begin
         if mCount > 0 then materials[mCount - 1].Emit := ParseVec3(line);
      end
      else if token = 'illum' then begin
         if mCount > 0 then begin
            dummy := StrToIntDef(Trim(Copy(line, Pos(' ', line) + 1, MaxInt)), 0);
            if dummy = 3 then materials[mCount - 1].Refl := SPEC
            else if dummy >= 4 then materials[mCount - 1].Refl := REFR;
         end;
      end
      else if token = 'Ni' then begin
         if mCount > 0 then materials[mCount - 1].Refl := REFR;
      end;
   end;
   CloseFile(fMtl);

   // マテリアルインスタンスの事前生成
   for i := prevMCount to mCount - 1 do begin
      materials[i].Tx := TextureClass.Create(materials[i].Emit, materials[i].Color);
      materials[i].Mat := CreateMaterialInstance(materials[i].Refl);
   end;
end;


{ ============================================================================
  メイン手続き LoadObjFile
  ============================================================================ }

procedure LoadObjFile(Dir, FN: string; Shapes: TList);
var
   f: TextFile;
   fullPath, line, token, tStr: string;
   vertices: array of Vec3;
   normals: array of Vec3;
   vCount, nCount, mCount, i: Integer;
   materials: TMaterialArray;
   curTx, defaultTx: TextureClass;
   curMat, defaultMat: MaterialClass;
   defColor, defEmit: Vec3;
begin
   if Dir <> '' then
      fullPath := IncludeTrailingPathDelimiter(Dir) + FN
   else
      fullPath := FN;

   writeln('Load ObjFile=', fullPath);
   if not Assigned(Shapes) then writeln('Shapes is not assigned!!');
   vCount := 0; nCount := 0; mCount := 0;
   
   // デフォルトマテリアルの生成
   defColor.New(0.8, 0.8, 0.8);
   defEmit.New(0.0, 0.0, 0.0);
   defaultTx := TextureClass.Create(defEmit, defColor);
   defaultMat := DiffuseClass.Create;
   curTx := defaultTx;
   curMat := defaultMat;

   if not FileExists(fullPath) then Exit;
   
   // OBJファイルのメイン解析ループ
   AssignFile(f, fullPath); Reset(f);
   while not Eof(f) do begin
      Readln(f, line); line := Trim(line);
      if line = '' then Continue;
      token := Copy(line, 1, Pos(' ', line + ' ') - 1);
      
      if token = 'mtllib' then begin
         tStr := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
         if tStr <> '' then LoadMtlFile(Dir, tStr, materials, mCount);
      end
      else if token = 'usemtl' then begin
         tStr := Trim(Copy(line, Pos(' ', line) + 1, MaxInt));
         for i := 0 to mCount - 1 do begin
            if materials[i].Name = tStr then begin
               curTx := materials[i].Tx;
               curMat := materials[i].Mat;
               Break;
            end;
         end;
      end
      else if token = 'v' then begin
         Inc(vCount); SetLength(vertices, vCount);
         vertices[vCount - 1] := ParseVec3(line);
      end
      else if token = 'vn' then begin
         Inc(nCount); SetLength(normals, nCount);
         normals[nCount - 1] := ParseVec3(line);
      end
      else if token = 'f' then begin
         ProcessFaceLine(line, vertices, normals, curTx, curMat, Shapes);
      end;
   end;
   CloseFile(f);
   Writeln(Format('Loaded OBJ: %d vertices, %d normals.', [vCount, nCount]));
end;


begin
   PolygonDumpFlag := false;
end.
