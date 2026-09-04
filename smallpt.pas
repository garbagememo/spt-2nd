program smallpt;
{$MODE objfpc}{$H+}
{$INLINE ON}
{$modeswitch advancedrecords}

uses SysUtils, Classes, Math, getopts, uBMP, uVect;

type
   RefType = (DIFF, SPEC, REFR); // Material types used in radiance()

   InterRecord = record
      isHit: boolean;
      t: real;
      id: integer;
   end;

   SphereClass = class
      rad: real;        // Radius
      p, e, c: Vec3;    // Position, emission, color
      refl: RefType;
      constructor Create(rad_: real; p_, e_, c_: Vec3; refl_: RefType);
      function intersect(const r: RayRecord): real;
   end;

constructor SphereClass.Create(rad_: real; p_, e_, c_: Vec3; refl_: RefType);
begin
   rad := rad_; p := p_; e := e_; c := c_; refl := refl_;
end;

function SphereClass.intersect(const r: RayRecord): real;
var
   op: Vec3;
   t, b, det: real;
begin
   op := p - r.o;
   t := eps; b := op * r.d; det := b * b - op * op + rad * rad;
   if det < 0 then 
      result := INF
   else begin
      det := sqrt(det);
      t := b - det;
      if t > eps then 
         result := t
      else begin
         t := b + det;
         if t > eps then 
            result := t
         else
            result := INF;
      end;
   end;
end;

var
   sph: TList;

procedure InitScene;
var
   p, c, e: Vec3;
begin
   sph := TList.Create;
   sph.add(SphereClass.Create(1e5,  Vec3.new(1e5 + 1, 40.8, 81.6),  ZeroVec, Vec3.new(0.75, 0.25, 0.25), DIFF)); // Left
   sph.add(SphereClass.Create(1e5,  Vec3.new(-1e5 + 99, 40.8, 81.6), ZeroVec, Vec3.new(0.25, 0.25, 0.75), DIFF)); // Right
   sph.add(SphereClass.Create(1e5,  Vec3.new(50, 40.8, 1e5),       ZeroVec, Vec3.new(0.75, 0.75, 0.75), DIFF)); // Back
   sph.add(SphereClass.Create(1e5,  Vec3.new(50, 40.8, -1e5 + 170), ZeroVec, Vec3.new(0, 0, 0),          DIFF)); // Front
   sph.add(SphereClass.Create(1e5,  Vec3.new(50, 1e5, 81.6),      ZeroVec, Vec3.new(0.75, 0.75, 0.75), DIFF)); // Bottom
   sph.add(SphereClass.Create(1e5,  Vec3.new(50, -1e5 + 81.6, 81.6),ZeroVec, Vec3.new(0.75, 0.75, 0.75), DIFF)); // Top
   sph.add(SphereClass.Create(16.5, Vec3.new(27, 16.5, 47),         ZeroVec, Vec3.new(1, 1, 1) * 0.999,  SPEC)); // Mirror
   sph.add(SphereClass.Create(16.5, Vec3.new(73, 16.5, 88),         ZeroVec, Vec3.new(1, 1, 1) * 0.999,  REFR)); // Glass
   sph.add(SphereClass.Create(600,  Vec3.new(50, 681.6 - 0.27, 81.6),Vec3.new(12, 12, 12), ZeroVec,      DIFF)); // Light
end;

function intersect(const r: RayRecord; var t: real; var id: integer): boolean;
var 
   d: real;
   i: integer;
begin
   t := INF;
   for i := 0 to sph.count - 1 do begin
      d := SphereClass(sph[i]).intersect(r);
      if d < t then begin
         t := d;
         id := i;
      end;
   end;
   result := (t < INF);
end;

function radiance(const r: RayRecord; depth: integer): Vec3;
var
   id: integer;
   obj: SphereClass;
   x, n, f, nl, u, v, w, d: Vec3;
   r1, r2, r2s, t: real;
   into: boolean;
   ray2, RefRay: RayRecord;
   nc, nt, nnt, ddn, cos2t, q, a, b, c,R0, Re, Tr, P, RP, TP: real;
   tDir: Vec3;
begin
   id := 0; depth := depth + 1;
   if not intersect(r, t, id) then begin
      result := ZeroVec;
      exit;
   end;
   
   obj := SphereClass(sph[id]);
   x := r.o + r.d * t; 
   n := (x - obj.p).Norm; 
   f := obj.c;
   
   if n.Dot(r.d) < 0 then nl := n else nl := n * -1;
   p := Max(f.x, Max(f.y, f.z));
   
   if depth > 5 then begin
      if random < p then 
         f := f / p 
      else 
         exit(obj.e);
   end;
   
   case obj.refl of
      DIFF: begin
         r1 := 2 * PI * random; 
         r2 := random; 
         r2s := sqrt(r2);
         w := nl;
         if abs(w.x) > 0.1 then
            u := (Vec3.new(0, 1, 0) / w).Norm 
         else
            u := (Vec3.new(1, 0, 0) / w).Norm;
         v := w / u;
         d := (u * cos(r1) * r2s + v * sin(r1) * r2s + w * sqrt(1 - r2)).Norm;
         result := obj.e + f.Mult(radiance(RayRecord.new(x, d), depth));
      end;
      
      SPEC: begin
         result := obj.e + f.Mult(radiance(RayRecord.new(x, r.d - n * 2 * (n * r.d)), depth));
      end;
      
      REFR: begin
         RefRay := RayRecord.new(x, r.d - n * 2 * (n * r.d));
         into := (n * nl > 0);
         nc := 1; nt := 1.5; 
         if into then nnt := nc / nt else nnt := nt / nc; 
         ddn := r.d * nl; 
         cos2t := 1 - nnt * nnt * (1 - ddn * ddn);
         
         if cos2t < 0 then begin // Total internal reflection
            result := obj.e + f.Mult(radiance(RefRay, depth));
            exit;
         end;
         
         if into then q := 1 else q := -1;
         tDir := (r.d * nnt - n * (q * (ddn * nnt + sqrt(cos2t)))).Norm;
         if into then q := -ddn else q := tDir * n;
         
         a := nt - nc; b := nt + nc; R0 := a * a / (b * b); c := 1 - q;
         Re := R0 + (1 - R0) * c * c * c * c * c; 
         Tr := 1 - Re; 
         P := 0.25 + 0.5 * Re; 
         RP := Re / P; 
         TP := Tr / (1 - P);
         
         if depth > 2 then begin
            if random < p then // 反射
               result := obj.e + f.Mult(radiance(RefRay, depth) * RP)
            else // 屈折
               result := obj.e + f.Mult(radiance(RayRecord.new(x, tDir), depth) * TP);
         end
         else begin // 屈折と反射の両方を追跡
            result := obj.e + f.Mult(radiance(RefRay, depth) * Re + radiance(RayRecord.new(x, tDir), depth) * Tr);
         end;
      end;
   end;
end;

var
   x, y, sx, sy, s: integer;
   w, h, samps: integer;
   cam: CamRecord;
   tColor, r: Vec3;
   BMP: BMPRecord;
   ArgInt: integer;
   FN, ArgFN: string;
   c: char;
   ray2: RayRecord;

begin
   FN := 'temp.bmp';
   w := 1024; h := 768; samps := 16;
   c := #0;
   
   repeat
      c := getopt('ho:s:w:');
      case c of
         'o': begin
            ArgFN := OptArg;
            if ArgFN <> '' then FN := ArgFN;
         end;
         's': begin
            ArgInt := StrToInt(OptArg);
            samps := ArgInt;
            writeln('samples =', ArgInt);
         end;
         'w': begin
            ArgInt := StrToInt(OptArg);
            w := ArgInt; h := w * 3 div 4;
            writeln('w=', w, ' ,h=', h);
         end;
         '?', 'h': begin
            writeln(' -o [filename] output filename');
            writeln(' -s [samps] sampling count');
            writeln(' -w [width] screen width pixel');
            halt;
         end;
      end;
   until c = endofoptions;

   writeln('sample=', samps);
   writeln('output file=', FN);
   
   BMP.new(w, h);
   InitScene;
   Randomize;

   cam := CamRecord.new(DefaultPosition, DefaultDirection, w, h, samps);
   writeln('The time is : ', TimeToStr(Time));

   for y := 0 to h - 1 do begin
      if y mod 10 = 0 then writeln('y=', y);
      for x := 0 to w - 1 do begin
         tColor := ZeroVec;
         for sy := 0 to 1 do begin
            for sx := 0 to 1 do begin
               r := ZeroVec;
               for s := 0 to samps - 1 do begin
                  ray2 := cam.GetRay(x, y, sx, sy);
                  r := r + radiance(ray2, 0) / samps;
               end;
               tColor := tColor + ClampVector(r) * 0.25;
            end;
         end;
         BMP.SetPixel(x, h - y - 1, ColToRGB(tColor));
      end;
   end;
   
   writeln('The time is : ', TimeToStr(Time));
   
   // uBMPのWriteFileにより拡張子に応じて適切な形式で自動保存
   BMP.WriteFile(FN);
end.
