# Oberon-importing-string-constants
Modified Oberon-07 compiler that allows exporting and re-importing of string constants.

Note: In this repository, the term "Project Oberon 2013" refers to a re-implementation of the original "Project Oberon" on an FPGA development board around 2013, as published at www.projectoberon.com.

**PREREQUISITES**: A current version of Project Oberon 2013 (see http://www.projectoberon.com). If you use Extended Oberon (see http://github.com/andreaspirklbauer/Oberon-extended), the functionality is already implemented.

------------------------------------------------------
The official Oberon-07 **language report** (http://www.inf.ethz.ch/personal/wirth/Oberon/Oberon07.Report.pdf, as of May 3, 2016) allows exporting of string constants, but the official compiler at www.projectoberon.com yields incorrect results.

The modified Oberon-07 compiler provided in **this** repository fixes that. This implementation is a superset of the implementation at https://github.com/andreaspirklbauer/Oberon-no-access-to-intermediate-objects.

------------------------------------------------------
**Implementation**

Points 1-5 are identical to https://github.com/andreaspirklbauer/Oberon-no-access-to-intermediate-objects, i.e.

1. First, we recall that when a string is parsed, a string item x is created in *ORP.factor* using *ORG.MakeStringItem*, where *x.a* is set to the string buffer position (*strx*) and *x.b* to the string length (*len*). There are two cases: *declared* and *anonymous* string constants.

         MODULE M;
           CONST s* = "declared string";  (*creates a named type in the symbol table of the compiler*)
           VAR a: ARRAY 32 OF CHAR;
         BEGIN a := "anonymous string"
         END M.

2. The field *obj.lev* is no longer "abused" to hold the length (*len*) of string constants. Instead, the length of a string constant is now encoded and stored together with its string buffer position (*strx*) in the field *obj.val*. This adds a single line to procedure *ORP.Declarations*

        IF x.type.form = ORB.String THEN obj.val := x.a (*strx*) + x.b (*len*) * 100000H ELSE obj.val := x.a END

     We have chosen to use the the 20 least significant bits (bits 0-19) to hold the string buffer position *strx* and the 12 most significant bits (bits 20-31) to hold the string length *len* (allowing for a maximum string length of 2^12 = 4096). This allows us to use the *same* code for decoding *obj.val* in procedure *ORG.MakeItem*, regardless of whether the object *obj* represents a global string (in which case the 20 lowest-order bits represent the string buffer position *strx*) or an imported string (in which case these bits represent the exporting module's export number *exno*):

        x.a := y.val MOD 100000H; (*strx/exno*) x.b := y.val DIV 100000H (*len*)

3. The field *obj.lev* holding the scope level is now consistently set for *all* declared objects, i.e. also for *constants*, *types* and *procedures*, not just for *variables* (by convention, *obj.lev = 0* for *global* objects, *obj.lev = level > 0* for local objects, and *obj.lev = -mno < 0* for *imported* objects, see *ORB.Import*). This makes it possible to check *all* identifiers for a valid scope.

4. The check for a valid scope level has been moved from *ORG.MakeItem* to *ORP.qualident*. This disallows access to *all* intermediate identifiers, and also in *all* cases when an item is *used*, not just when it is initially *created*.

5. Intermediate *procedures* are excluded from the check, as we *want* them to remain accessible in nested scopes.

Points 6-12 are specific to *this* repository https://github.com/andreaspirklbauer/Oberon-importing-string-constants:

The basic idea is that exported string constants are treated like a pre-initialized, immutable exported variables.

6. When a string constant is *exported* using procedure *ORB.Export*, a *symbol* file entry is created such that it holds the export number (*obj.exno*) and the string length (*len* = *obj.val DIV 100000H*) in encoded form, but *not* the string buffer position (which is ignored during export because symbol files must not contain absolute addresses; see below). The export number is stored in the least significant 20 bits (bits 0-19), the string length in the most significant 12 bits (bits 20-31) of the symbol file entry. This adds a single line to procedure *ORB.Export*:

        IF obj.class = Const THEN
          ...
          ELSIF obj.type.form = String THEN Files.WriteNum(R, obj.exno + obj.val DIV 100000H (*len*) * 100000H)

7. When a string constant is *imported* by another module using procedure *ORB.Import*, a symbol table entry *obj* with the field *obj.val* holding the export number (*exno*) and the string length (*len*) using the above encoding is created. No changes are required in *ORB.Import*, as this case is already covered by the statement *Files.ReadNum(R, obj.val)* in the line:

        IF obj.class = Const THEN
          ...
          IF obj.type.form = Real THEN Files.ReadInt(R, obj.val) ELSE Files.ReadNum(R, obj.val) END

8. When an imported string is accessed during code generation, an item x is created in procedure *ORG.MakeItem*, which decodes the value of *obj.val* and stores the export number (*exno*) in the field *x.a*, the string length (*len*) in *x.b* and the module number (*mno*) in *x.r* (0 = global, negative = imported). This changes procedure *ORG.MakeItem* to:

        ELSIF (y.class = ORB.Const) & (y.type.form = ORB.String) THEN x.r := y.lev; (*mno*)
          x.a := y.val MOD 100000H; (*strx / exno*) x.b := y.val DIV 100000H (*len*)

     Note that procedure *ORG.MakeStringItem*, which is used only for global, but not for imported strings, also sets *x.r* to 0 (*global*). This is now necessary in order to allow procedure *ORG.loadStringAdr* to distinguish between the two cases (see next point).

9. When code is generated involving an *imported* string, the export number (*exno*) stored in the field *x.a* is inserted in the code stream for later fixup by the module loader. This changes the following instructions in *ORG.loadStringAdr*

    from:


        GetSB(0); Put1a(Add, RH, RH, varsize+x.a)

    to:

        IF x.r >= 0 THEN GetSB(0); Put1a(Add, RH, RH, varsize+x.a)  (*strx converted to SB-relative*)
        ELSE (*imported*) GetSB(x.r); Put1(Add, RH, RH, x.a)  (*exno*)
        END ;

10. In addition to adding a *symbol file* entry for each exported string constant, the *entries* section of the *object* file of the exporting module (offsets of all exported entities) now also contains an entry for each exported string constant holding its string buffer position (*strx*), converted to SB-relative, i.e. the offset relative to the static base (SB) of the exporting module. This adds 2 lines to *ORG.Close*:

        IF (obj.class = ORB.Const) & (obj.type.form = ORB.String) THEN
          Files.WriteInt(R, varsize + obj.val MOD 100000H) (*strx converted to SB-relative*)


11. When the *exporting* module is loaded by the loader, an *entry* for each exported string is created in the *entries* section of the module block (in memory), accessible via the link *mod.ent*. We recall that this section is used by the loader for linking client modules to already loaded modules (see point 11).

12. Finally, when a module *importing* a string constant is loaded, the module loader "fixes up" all load instructions and replaces them with the actual string buffer position (*strx*) of the imported string within the exporting module, using the export number (*exno*) to access the corresponding entry in the *entries* section of the exporting module (see the code at the end of *Modules.Load*).

The mechanism described in points 10 - 12 are already in place in the Oberon system (for other exported objects such as variables and procedures), and hence required no additional implementation effort.

*Final comment:* It is absolutely essential that the symbol file does *not* contain the string buffer position (*strx*), i.e. an address, of the exported string constant. If it did, any change in the source file of the exporting module might change that address (even if the string itself has not changed). But this would contradict the postulate of *separate compilation*, which states that *changes* in the implementation of a module M do *not* invalidate clients of M, if the *interface* of M remains unaffected.

------------------------------------------------------
**Differences to the official Oberon-07 compiler**

In the output of the following Unix-style *diff* commands, lines that begin with "<" are the old lines (i.e. code from the official Oberon-07 compiler), while lines that begin with ">" are the modified lines (i.e. code from *this* repository).

**$ diff FPGAOberon2013/ORB.Mod ORB.Mod**

*ORB.Export:*

```diff
327a328
>           ELSIF obj.type.form = String THEN Files.WriteNum(R, obj.exno + obj.val DIV 100000H (*len*) * 100000H)
```

**$ diff FPGAOberon2013/ORG.Mod ORG.Mod**


*ORG.loadStringAdr:*

```diff
226c226,228
BEGIN GetSB(0); Put1a(Add, RH, RH, varsize+x.a); x.mode := Reg; x.r := RH; incR
---
>   BEGIN
>     IF x.r >= 0 THEN GetSB(0); Put1a(Add, RH, RH, varsize+x.a) ELSE GetSB(x.r); Put1(Add, RH, RH, x.a) (*exno*) END ;
>     x.mode := Reg; x.r := RH; incR
```

*ORG.MakeStringItem:*

```diff
241c243
<   BEGIN x.mode := ORB.Const; x.type := ORB.strType; x.a := strx; x.b := len; i := 0;
---
>   BEGIN x.mode := ORB.Const; x.type := ORB.strType; x.a := strx; x.b := len; x.r := 0; i := 0;
```

*ORG.MakeItem:*

```diff
252c254,255
<     ELSIF (y.class = ORB.Const) & (y.type.form = ORB.String) THEN x.b := y.lev  (*len*)
---
>     ELSIF (y.class = ORB.Const) & (y.type.form = ORB.String) THEN x.r := y.lev;
>       x.a := y.val MOD 100000H; (*strx / exno*) x.b := y.val DIV 100000H (*len*)
254,255c257
<     END ;
<     IF (y.lev > 0) & (y.lev # curlev) & (y.class # ORB.Const) THEN ORS.Mark("level error, not accessible") END
---
>     END
```

*ORG.Close:*

```diff
1098,1099c1100,1103
<         IF (obj.class = ORB.Const) & (obj.type.form = ORB.Proc) OR (obj.class = ORB.Var) THEN
<           Files.WriteInt(R, obj.val);
---
>         IF (obj.class = ORB.Const) & (obj.type.form = ORB.String) THEN
>           Files.WriteInt(R, varsize + obj.val MOD 100000H) (*strx converted to SB-relative*)
>         ELSIF (obj.class = ORB.Const) & (obj.type.form = ORB.Proc) OR (obj.class = ORB.Var) THEN
>           Files.WriteInt(R, obj.val)
```
     
**$ diff FPGAOberon2013/ORP.Mod ORP.Mod**

*ORP.qualident:*

```diff
39a40,41
>     ELSIF (obj.lev > 0) & (obj.lev # level) &
>       ((obj.class # ORB.Const) OR (obj.type.form # ORB.Proc)) THEN ORS.Mark("not accessible")
```

*ORP.Declarations:*

```diff
797,798c799,802
<         ORB.NewObj(obj, id, ORB.Const); obj.expo := expo;
<         IF x.mode = ORB.Const THEN obj.val := x.a; obj.lev := x.b; obj.type := x.type
---
>         ORB.NewObj(obj, id, ORB.Const); obj.expo := expo; obj.lev := level;
>         IF x.mode = ORB.Const THEN obj.type := x.type;
>           IF expo & (obj.type.form = ORB.String) THEN obj.exno := exno; INC(exno) ELSE obj.exno := 0 END ;
>           IF obj.type.form = ORB.String THEN obj.val := x.a (*strx*) + x.b (*len*) * 100000H ELSE obj.val := x.a END
```

------------------------------------------------------
**Preparing your system to use the modified Oberon compiler**

If *Extended Oberon* is used, exporting and importing of string constants is already implemented on your system.

If *Project Oberon 2013* is used, follow the instructions below:

------------------------------------------------------

Convert the downloaded files to Oberon format (Oberon uses CR as line endings) using the command [**dos2oberon**](dos2oberon), also available in this repository (example shown for Mac or Linux):

     for x in *.Mod ; do ./dos2oberon $x $x ; done

Import the files to your Oberon system. If you use an emulator (e.g., **https://github.com/pdewacht/oberon-risc-emu**) to run the Oberon system, click on the *PCLink1.Run* link in the *System.Tool* viewer, copy the files to the emulator directory, and execute the following command on the command shell of your host system:

     cd oberon-risc-emu
     for x in *.Mod ; do ./pcreceive.sh $x ; sleep 0.5 ; done

Compile the provided test programs *Test1* (exports a string constant) and *Test2* (imports a string constant) with the MODIFIED Oberon compiler:

     ORP.Compile ORB.Mod/s ORG.Mod/s ORP.Mod/s ~
     System.Free ORTool ORP ORG ORB ~

     ORP.Compile Test1.Mod/s Test2.Mod/s ~
     System.Free Test2 Test1 ~

     Test2.Import1
     Test2.Import2
     Test2.Import3

     Test2.Global1
     Test2.Global2
     Test2.Global3
