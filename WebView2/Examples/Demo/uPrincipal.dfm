object frmPrincipal: TfrmPrincipal
  Left = 200
  Top = 120
  Width = 1100
  Height = 700
  Caption = 'WebView2 + Delphi 7'
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
  object splLateral: TSplitter
    Left = 791
    Top = 37
    Width = 4
    Height = 607
    Cursor = crHSplit
    Align = alRight
  end
  object pnlTopo: TPanel
    Left = 0
    Top = 0
    Width = 1092
    Height = 37
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    DesignSize = (
      1092
      37)
    object btnVoltar: TButton
      Left = 6
      Top = 6
      Width = 32
      Height = 25
      Hint = 'Voltar'
      Caption = '<'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 0
      OnClick = btnVoltarClick
    end
    object btnAvancar: TButton
      Left = 40
      Top = 6
      Width = 32
      Height = 25
      Hint = 'Avan'#231'ar'
      Caption = '>'
      ParentShowHint = False
      ShowHint = True
      TabOrder = 1
      OnClick = btnAvancarClick
    end
    object btnRecarregar: TButton
      Left = 74
      Top = 6
      Width = 70
      Height = 25
      Caption = 'Recarregar'
      TabOrder = 2
      OnClick = btnRecarregarClick
    end
    object edtUrl: TEdit
      Left = 150
      Top = 8
      Width = 786
      Height = 21
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 3
      OnKeyPress = edtUrlKeyPress
    end
    object btnIr: TButton
      Left = 942
      Top = 6
      Width = 50
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Ir'
      TabOrder = 4
      OnClick = btnIrClick
    end
    object btnDevTools: TButton
      Left = 998
      Top = 6
      Width = 88
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'DevTools'
      TabOrder = 5
      OnClick = btnDevToolsClick
    end
  end
  object pnlLateral: TPanel
    Left = 795
    Top = 37
    Width = 297
    Height = 607
    Align = alRight
    BevelOuter = bvNone
    BorderWidth = 6
    TabOrder = 1
    object grpPonte: TGroupBox
      Left = 6
      Top = 6
      Width = 285
      Height = 187
      Align = alTop
      Caption = ' Ponte Delphi <-> JavaScript '
      TabOrder = 0
      DesignSize = (
        285
        187)
      object lblMensagem: TLabel
        Left = 10
        Top = 20
        Width = 140
        Height = 13
        Caption = 'Mensagem para a p'#225'gina:'
      end
      object lblScript: TLabel
        Left = 10
        Top = 82
        Width = 101
        Height = 13
        Caption = 'Script a executar:'
      end
      object edtMensagem: TEdit
        Left = 10
        Top = 36
        Width = 265
        Height = 21
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 0
        Text = 'Ol'#225' do Delphi 7!'
      end
      object btnEnviarJS: TButton
        Left = 10
        Top = 58
        Width = 120
        Height = 22
        Caption = 'PostWebMessage'
        TabOrder = 1
        OnClick = btnEnviarJSClick
      end
      object edtScript: TEdit
        Left = 10
        Top = 98
        Width = 265
        Height = 21
        Anchors = [akLeft, akTop, akRight]
        TabOrder = 2
        Text = 'somar(20, 22)'
      end
      object btnExecutarJS: TButton
        Left = 10
        Top = 120
        Width = 120
        Height = 22
        Caption = 'ExecuteScript'
        TabOrder = 3
        OnClick = btnExecutarJSClick
      end
      object btnPaginaDemo: TButton
        Left = 10
        Top = 152
        Width = 120
        Height = 25
        Caption = 'P'#225'gina de demo'
        TabOrder = 4
        OnClick = btnPaginaDemoClick
      end
    end
    object rgNovaJanela: TRadioGroup
      Left = 6
      Top = 193
      Width = 285
      Height = 100
      Align = alTop
      Caption = ' Novas janelas (NewWindowRequested) '
      ItemIndex = 0
      Items.Strings = (
        'Abrir na mesma janela'
        'Popup do WebView2 (padr'#227'o)'
        'Bloquear'
        'Abrir no navegador padr'#227'o')
      TabOrder = 2
    end
    object grpLog: TGroupBox
      Left = 6
      Top = 293
      Width = 285
      Height = 308
      Align = alClient
      Caption = ' Log '
      TabOrder = 1
      object memLog: TMemo
        Left = 2
        Top = 15
        Width = 281
        Height = 391
        Align = alClient
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Courier New'
        Font.Style = []
        ParentFont = False
        ReadOnly = True
        ScrollBars = ssBoth
        TabOrder = 0
        WordWrap = False
      end
    end
  end
  object sbStatus: TStatusBar
    Left = 0
    Top = 644
    Width = 1092
    Height = 19
    Panels = <
      item
        Width = 140
      end
      item
        Width = 50
      end>
  end
end
