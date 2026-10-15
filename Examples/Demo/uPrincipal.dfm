object frmPrincipal: TfrmPrincipal
  Left = 200
  Top = 120
  Width = 1000
  Height = 640
  Caption = 'Borion Demo'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object splBase: TSplitter
    Left = 0
    Top = 447
    Width = 992
    Height = 4
    Cursor = crVSplit
    Align = alBottom
  end
  object pnlBase: TPanel
    Left = 0
    Top = 451
    Width = 992
    Height = 155
    Align = alBottom
    BevelOuter = bvNone
    BorderWidth = 6
    TabOrder = 0
    object grpEmitir: TGroupBox
      Left = 6
      Top = 6
      Width = 260
      Height = 143
      Align = alLeft
      Caption = ' Delphi -> p'#225'gina (Ipc.Emit) '
      TabOrder = 0
      object lblMensagem: TLabel
        Left = 10
        Top = 20
        Width = 53
        Height = 13
        Caption = 'Mensagem:'
      end
      object edtMensagem: TEdit
        Left = 10
        Top = 36
        Width = 238
        Height = 21
        TabOrder = 0
        Text = 'Ol'#225' da janela Delphi!'
      end
      object btnEmitir: TButton
        Left = 10
        Top = 62
        Width = 238
        Height = 25
        Caption = 'Emitir "delphi:mensagem"'
        Enabled = False
        TabOrder = 1
        OnClick = btnEmitirClick
      end
      object btnDevTools: TButton
        Left = 10
        Top = 106
        Width = 238
        Height = 25
        Caption = 'DevTools'
        Enabled = False
        TabOrder = 2
        OnClick = btnDevToolsClick
      end
    end
    object memLog: TMemo
      Left = 266
      Top = 6
      Width = 720
      Height = 143
      Align = alClient
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Courier New'
      Font.Style = []
      ParentFont = False
      ReadOnly = True
      ScrollBars = ssBoth
      TabOrder = 1
      WordWrap = False
    end
  end
end
