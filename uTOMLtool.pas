unit uTOMLtool;

interface

{$mode objfpc}{$H+}{$M+}
{$codepage UTF8}

uses
   {$IFDEF UNIX}
   cthreads,cmem,
   cwstring,
   {$ENDIF}
   {$IFDEF WINDOWS}
   Windows,
   {$ENDIF}
   SysUtils, Classes, StrUtils, Generics.Collections,
   uVect,uShape,uRadiance,uTOML;


type
   SPTOMLDocument=class(TOMLDocument)
   private
      FBVHCount:integer;
      FBVHVal:TOMLValue;
   public
      constructor create(FN:string);
      function CamNew:CamRecord;
      function KeyToVec3(KeyName:string):Vec3;
      function ObjKeyToVec3(OT:TOMLtable;KeyName:string):Vec3;
      function GetShapeList:ShapeListClass;
      procedure GetBVHListArray;
      function GetBVHList(i:integer):BVHListClass;
      procedure AddBVHList(var sc:SceneRecord);
      property BVHCount:integer read FBVHCount;
   end;

  
implementation

constructor SPTOMLDocument.create(FN:string);
begin
   inherited create;
   LoadFromFile(FN);
end;

function SPTOMLDocument.KeyToVec3(KeyName:string):Vec3;
var
   Val:TOMLValue;
   PosArray: TOMLArray;
begin
   Val := GetValueByPath(KeyName);
   if (Val <> nil) and (Val.ValueType = tvtArray) then begin
      PosArray := Val.AsArray;
      result.new( PosArray[0].AsFloat,PosArray[1].AsFloat,PosArray[2].AsFloat);
   end
   else
      result:=INFVec;
end;

function SPTOMLDocument.ObjKeyToVec3(OT:TOMLtable;KeyName:string):Vec3;
var
   PosArray:TOMLArray;
begin
   PosArray := OT.GetArray(KeyName);
   if (PosArray <> nil) then 
      result.new( PosArray[0].AsFloat,PosArray[1].AsFloat,PosArray[2].AsFloat);
end;      

function SPTOMLDocument.GetShapeList:ShapeListClass;
var
   ObjArrayVal: TOMLValue;
   ObjTable,TextureTable: TOMLTable;
   i: integer;
   ShapeList:ShapeListClass;
   sh:ShapeClass;
   r:real;c,e,p:Vec3;refl:RefType;
begin
   // 'objects' 全体の配列を取得
   ObjArrayVal := GetValueByPath('objects');

   if (ObjArrayVal <> nil) and (ObjArrayVal.ValueType = tvtArray) then begin
      ShapeList:=ShapeListClass.Create;
      
      WriteLn('オブジェクト総数: ', ObjArrayVal.AsArray.Count);

      for i:=0 to ObjArrayVal.AsArray.Count-1 do begin
         ObjTable := ObjArrayVal.AsArray[i].AsTable;
         if ObjTable.GetString('shape')='sphere' then begin
            r:=ObjTable.GetFloat('radius');
            p:=ObjKeyToVec3(ObjTable,'position');
            e:=ObjKeyToVec3(ObjTable,'emission');
            c:=ObjKeyToVec3(ObjTable,'color');
            refl:=StrToRefl(ObjTable.GetString('material') );
            sh:=SphereClass.Create(r,p,e,c,refl);
            if ObjTable.GetString('texture')<>'' then begin
               TextureTable := ObjTable.GetTable('ring');
               if TextureTable <> nil  then begin
                  sh.tx:=RingTextureClass.create(e,c,
                                                 ObjKeyToVec3(TextureTable,'center'),
                                                 ObjKeyToVec3(TextureTable,'modify'));
               end;
               TextureTable := ObjTable.GetTable('bmp');
               if TextureTable<>nil then begin
                  sh.tx:=SphereBMPTextureClass.create(e,c,SphereClass(sh).p,
                                                      ObjFilePath,
                                                      TextureTable.GetString('filename'));
                  end;
            end;            
            ShapeList.add(sh );
         end
         else if ObjTable.GetString('shape')='obj' then begin
            ShapeList.LoadObj(ObjFilePath,ObjTable.GetString('filename') );
         end;
      end;
      result:=ShapeList;
   end
   else begin
      result:=nil;
   end;
end;

procedure SPTOMLDocument.GetBVHListArray;
begin
      // 'BVH' 全体の配列を取得
   FBVHVal := GetValueByPath('BVH');

   if (FBVHVal <> nil) and (FBVHVal.ValueType = tvtArray) then begin
      WriteLn('BVHオブジェクト総数: ', FBVHVal.AsArray.Count);
      FBVHCount:=FBVHVal.AsArray.Count;
   end
   else begin
      FBVHVal:=nil;
      FBVHCount:=0;
   end;   
end;

function SPTOMLDocument.GetBVHList(i:integer):BVHListClass;
var
   ObjTable,TextureTable:TOMLTable;
   bvh:BVHListClass;
   tx:TextureClass;
   j:integer;
begin
   if (i<0) or (i>FBVHCount-1) then begin result:=nil; exit;end;
   ObjTable := FBVHVal.AsArray[i].AsTable;
   if ObjTable.GetString('shape')='obj' then begin
      bvh:=BVHListClass.Create;
      bvh.LoadObj(ObjFilePath,ObjTable.GetString('filename') );
      result:=bvh;
      TextureTable := ObjTable.GetTable('bmp');
      if TextureTable<>nil then begin
         tx:=SphereBMPTextureClass.create(zeroVec,zeroVec,bvh.cen,
                                          ObjFilePath,
                                          TextureTable.GetString('filename'));
         for j:=0 to bvh.shapes.count-1 do ShapeClass(bvh.shapes[j]).tx:=tx;            
      end;
   end;
end;

procedure SPTOMLDocument.AddBVHList(var sc:SceneRecord);
var
   i:integer;
begin
   GetBVHListArray;
   for i:=0 to BVHCount-1 do sc.scList.add(GetBVHList(i));
end;

function SPTOMLDocument.CamNew:CamRecord;
var
   cam:CamRecord;
   w,h,samps:integer;
   o,d:Vec3;
   dist:real;
   Val:TOMLValue;
begin
   Val := GetValueByPath('camera.width');
   if Val<>nil then w:=Val.asInt else w:=640;
   Val := GetValueByPath('camera.height');     
   if Val<>nil then h:=Val.asInt else h:=480;
   Val := GetValueByPath('camera.samples');     
   if Val<>nil then samps:=Val.asInt else samps:=16;
   Val := GetValueByPath('camera.plane_distancet');     
   if Val<>nil then dist:=Val.asFloat else dist:=140;

   o:=KeyToVec3('camera.position');
   if isINF(o) then o:=DefaultPosition;
   
   d:=KeyToVec3('camera.direction');
   if isINF(d) then d:=DefaultDirection;
   result:=cam.new(o,d,w,h,samps);
   cam.PlaneDist:=dist;
end;

begin
end.
