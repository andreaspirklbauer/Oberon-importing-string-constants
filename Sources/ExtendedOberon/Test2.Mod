MODULE Test2;
  IMPORT Texts, Oberon, Test1;

  CONST b = "B";
    string2 = "Global string string2 from module Test2";
  VAR W: Texts.Writer;
    s: ARRAY 64 OF CHAR;
    c: CHAR;

  PROCEDURE Import1*; (*imported string from module Test1*)
  BEGIN s := Test1.string1; Texts.WriteString(W, s); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END Import1;

  PROCEDURE Import2*; (*imported character from module Test1*)
  BEGIN c := Test1.a; Texts.Write(W, c); Texts.WriteString(W, " (exported character a from module Test1)");
    Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END Import2;

  PROCEDURE Import3*; (*pass an imported string to a procedure*)
    PROCEDURE P(s: ARRAY OF CHAR);
    BEGIN Texts.WriteString(W, s); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
    END P;
  BEGIN P(Test1.string1)
  END Import3;

  PROCEDURE Global1*; (*global string*)
  BEGIN s := string2; Texts.WriteString(W, s); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END Global1;

  PROCEDURE Global2*; (*global char*)
  BEGIN c := b; Texts.Write(W, c); Texts.WriteString(W, " (global character b from module Test2)");
    Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
  END Global2;

  PROCEDURE Global3*; (*pass a global string to a procedure*)
    PROCEDURE P(s: ARRAY OF CHAR);
    BEGIN Texts.WriteString(W, s); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
    END P;
  BEGIN P(string2)
  END Global3;

BEGIN Texts.OpenWriter(W)
END Test2.

ORP.Compile ORB.Mod/s ORG.Mod/s ORP.Mod/s ~
System.Free ORTool ORP ORG ORB ~

ORP.Compile Test1.Mod/s Test2.Mod/s ~
System.Free Test2 Test1 ~

ORTool.DecObj Test2.rsc

Test2.Import1
Test2.Import2
Test2.Import3

Test2.Global1
Test2.Global2
Test2.Global3



