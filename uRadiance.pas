unit uRadiance;
{$MODE objfpc}{$H+}
{$INLINE ON}
{$modeswitch advancedrecords}

interface
uses SysUtils,Classes,uVect,uBMP,Math,getopts,uShape,uBVH,uObjShape;

type
   ShapeListClass=Class
      shapes:TList;
      constructor create;
      procedure add(s : ShapeClass);
      function intersect(const r: RayRecord):HitInfo;virtual;
      function GetObj(id:integer):ShapeClass;virtual;
      procedure LoadObj(ObjPath:string;FN:string);virtual;
   end;
   
   BVHListClass = class(ShapeListClass)
      bvh:BVHNodeClass;
      cen:Vec3;
      function intersect(const r:RayRecord):HitInfo;override;
      procedure LoadObj(ObjPath:string;FN:string);override;
      procedure MakeBVHNode;
   end;

   SceneRecord = record
      scList:TList;//List of SceneListClass
      cam:CamRecord;
      procedure new(w,h,samps:integer);
      function Radiance(const r:RayRecord;depth:integer):Vec3;
   end;

var
    ObjFilePath:string='obj';
   
implementation
constructor ShapeListClass.create;
begin
   Shapes:=TList.Create;
end;
procedure ShapeListClass.add(s: ShapeClass);
begin
   Shapes.add(s);
end;

function ShapeListClass.intersect(const r:RayRecord):HitInfo;
var 
  t,d:real;
  i,id:integer;
  Info:InterInfo;
begin
   result.isHit:=false;
   result.t:=INF;
   t:=INF;
   id:=Shapes.count-1;
   for i:=0 to Shapes.count-1 do begin
      Info:=ShapeClass(Shapes[i]).intersect(r);
      d:=Info.t;
      if d < t then begin
         t:=d;
         id:=i;
      end;
   end;
   result.isHit:=(t<inf);
   if result.isHit then begin
      result.t:=t;
      result.id:=id;
   end;
end;

function ShapeListClass.GetObj(id:integer):ShapeClass;
begin
   result:=ShapeClass(shapes[id]);
end;

procedure ShapeListClass.LoadObj(ObjPath:string;FN:string);
begin
   LoadObjFile(ObjPath,FN,Shapes);
end;

function BVHListClass.intersect(const r:RayRecord):HitInfo;
begin
   result.obj:=nil;
   result:=bvh.intersect(r,shapes);
end;

procedure BVHListClass.MakeBVHNode;
var
   ary:array of integer;
   i:integer;
begin
   SetLength(ary,shapes.count);
   writeln('bvh sph.count=',shapes.count);
   for i:=0 to shapes.count-1 do ary[i]:=i;
   bvh:=BVHNodeClass.Create(ary,0,high(ary),shapes);
   cen.x:=(bvh.root.little.x+bvh.root.large.x)/2;
   cen.y:=(bvh.root.little.y+bvh.root.large.y)/2;
   cen.z:=(bvh.root.little.z+bvh.root.large.z)/2;
end;

procedure BVHListClass.LoadObj(ObjPath:string;FN: string);
begin
   LoadObjFile(ObjPath,FN,Shapes);
   MakeBVHNode
end;

procedure SceneRecord.new(w,h,samps:integer);
var
   camPosition,camDirection : Vec3;
begin
   scList:=TList.create;
   cam.new(camPosition.new(50, 52, 295.6),camDirection.new(0, -0.042612, -1).norm,w,h,samps );
end;

function SceneRecord.Radiance(const r:RayRecord;depth:integer):Vec3;
var
   f,x,n,nl:Vec3;
   p:real;
   hit,hit2:HitInfo;
   tInfo:TraceInfo;
   i:integer;
begin
   depth:=depth+1;
   hit.isHit:=false;hit.t:=INF;
   i:=0;
   while i<scList.count do begin
      hit2:=ShapeListClass(scList[i]).intersect(r);
      if hit2.isHit then begin
         if hit.t>hit2.t then begin
            hit:=hit2;
            hit.obj:=ShapeListClass(scList[i]).GetObj(hit.id);
         end;
      end;
      i:=i+1;
   end;
   if hit.isHit=false then begin
      result:=ZeroVec;exit;
   end;
   x:=r.o+r.d*hit.t;
   n:=hit.obj.GetNorm(x);
   if n.dot(r.d)<0 then nl:=n else nl:=n*-1;
   f := hit.obj.tx.getColor(x);
   p:=Max(f.r,Max(f.g,f.b));
   if (depth>5) then begin
      if random<p then 
         f:=f/p 
      else
         Exit(hit.obj.tx.GetEmit(x));
   end;
   tInfo := hit.obj.m.GetRay(r,x,n,nl);
   result:=hit.obj.tx.GetEmit(x)+f.Mult(Radiance(tInfo.r,depth))*tInfo.cpc;
end;
begin
end.
