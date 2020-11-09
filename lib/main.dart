import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter_icons/flutter_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'globals.dart' as globals;
import 'correctionTable.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:badges/badges.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:bottom_navy_bar/bottom_navy_bar.dart';

Iterable<int> range(int low, int high) sync* {
  for (int i = low; i < high; ++i) {
    yield i;
  }
}

bool equalsIgnoreCase(String string1, String string2) {
  return string1?.toLowerCase() == string2?.toLowerCase();
}
BluetoothDevice _connectedDevice;
List<BluetoothService> _services;
FlutterBlue flutterBlue = FlutterBlue.instance;
List<BluetoothDevice> devicesList = new List<BluetoothDevice>();
Map<Guid, List<int>> readValues = new Map<Guid, List<int>>();
BluetoothDevice deviceKeyboard;
List<List<String>> correctionTable = List<List<String>>();

String beforeEdit = '';
String afterEdit = '';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    return MaterialApp(
      title: 'BLE Demo',
      theme: ThemeData(
        primaryColor: Colors.white,
        accentColor: Colors.lightBlueAccent,
        iconTheme: IconThemeData(
          color: Colors.blue,
        ),
        textTheme: GoogleFonts.montserratTextTheme(
            Theme.of(context).textTheme
        ),
      ),
      home: MyHomePage(title: 'Ludicrous Speed'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver, TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  double level = 0.0;
  double minSoundLevel = 50000;
  double maxSoundLevel = -50000;
  String lastWords = "";
  String lastError = "";
  String lastStatus = "";
  String _currentLocaleId = "";
  bool resizeScaffold = false;
  bool showSpecialKeys = false;
  String currentFileName;
  final SpeechToText speech = SpeechToText();
  FocusNode focusDude = FocusNode();
  Timer lockTimeout;
  Color indicatorColor;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      print(state.toString());
      if (state == AppLifecycleState.paused) {
        stopListening();
        micIcon = FlutterIcons.mic_ent;
      }
      if (state == AppLifecycleState.resumed) {
        checkConnectionStatus();
      }
    });
  }

  checkConnectionStatus() {
    setState(() {
      _activelyConnectingBool = true;
    });
    bool alreadyConnected = false;
    bool haveService = false;
    flutterBlue.connectedDevices
        .asStream()
        .listen((List<BluetoothDevice> devices) async {
      for (BluetoothDevice device in devices) {
        print(device.name);
        print('connected DEVICE:::: ' + device.name.toString());
        if (device.id.toString().substring(0, 10) == 'B29B4DAD-A') {
          alreadyConnected = true;
          print('resuming and already connected');
          _connectedDevice = device;
          if (writeCharacteristic == null) {
            print('do not have service saved discovering services now');
            _services = await device.discoverServices();
            for (BluetoothService service in _services) {
              for (BluetoothCharacteristic characteristic
                  in service.characteristics) {
                if (characteristic.uuid.toString().substring(0, 1) == '6') {
                  writeCharacteristic = characteristic;
                  setState(() {
                    _activelyConnectingBool = false;
                  });
                }
              }
            }
          } else {
            _activelyConnectingBool = false;
            haveService = true;
          }
        }
      }
      Future.delayed(
          const Duration(milliseconds: 1000),
          () => {
                print('timeout'),
                if (alreadyConnected)
                  {
                    if (!haveService)
                      {
                        if (_connectedDevice != null)
                          {
                            findService(_connectedDevice),
                          }
                        else
                          {}
                      }
                  }
                else
                  {
                    scanAndConnectDefault(),
                  }
              });
    });
  }

  findService(BluetoothDevice device) async {
    _services = await device.discoverServices();
    for (BluetoothService service in _services) {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.uuid.toString().substring(0, 1) == '6') {
          writeCharacteristic = characteristic;
        }
      }
    }
  }



  PageController tabCont = PageController(
    initialPage: 1,

  );
  int _selectedIndex = 1;
  @override
  void initState() {
    print('initializing');

    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initSpeechState();
    _loadPreferences();

    loadTable();
    Future.delayed(const Duration(milliseconds: 1000), () {
      checkConnectionStatus();
    });
    PageController tabCont = PageController(
      initialPage: 0,

    );


    openFiles();
  }

  loadTable() async {
    return
    print('loading table');
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String loadString = prefs.getString('table');
    //print('load string ' + loadString);
    if (loadString != null) {
      List<List<String>> load = List<List<String>>();
      List<String> rows = loadString.split('[');
      rows.removeAt(0);
      print(rows);
      for (String row in rows ) {
        List<String> sets = row.split(',');
        load.add([sets[0], sets[1]]);
      }
      globals.correctionTable = load;
      print('correction table loaded: ');
      print( load);
    }else{
      print('nothing to load');
    }
  }

  scanAndConnectDefault() async {
    print('device is  : ' + _connectedDevice.toString());
    if (_connectedDevice != null) {
      setState(() {
        _activelyConnectingBool = true;
      });
      print('disconnecting device');
      _connectedDevice.disconnect();
      print('disconnected');
      _connectedDevice = null;
      setState(() {
        _activelyConnectingBool = false;
      });
    } else {
      setState(() {
        _activelyConnectingBool = true;
      });
      print('starting scan auto connect');

      flutterBlue.startScan(
        timeout: Duration(seconds: 4),
      );

      int timesEntered = 0;
      flutterBlue.scanResults.listen((List<ScanResult> results) {
        for (ScanResult result in results) {
          print("found in autoconnect: " + result.device.id.toString());
          if (result.device.id.toString().substring(0, 10) == 'B29B4DAD-A') {
            print('resulted target BLE device');
            try {
              print('entering try');
              _tryConnect(result.device);
            } catch (e) {
              print('error: ' + e.toString());
              if (e.code != 'already_connected') {
                throw e;
              } else {}
            } finally {
              timesEntered = timesEntered + 1;
              print('entered ' + timesEntered.toString());
              if (timesEntered > 2) {
                print('scan stopped now in finally');
                flutterBlue.stopScan();
              }
            }
          }
        }
      });
      Future.delayed(const Duration(milliseconds: 4000), () {
        flutterBlue.stopScan();
        print('end of scaning');
        setState(() {
          _activelyConnectingBool = false;
        });
      });
    }
  }

  _tryConnect(final BluetoothDevice device) async {
    print('trying to connect');

    try {
      await device.connect();
    } catch (e) {
      print(e.toString());
      if (e.code != 'already_connected') {
        throw e;
      } else {}
    } finally {
      print('nailed it finding services');
      _services = await device.discoverServices();
      for (BluetoothService service in _services) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid.toString().substring(0, 1) == '6') {
            writeCharacteristic = characteristic;

          }
        }
      }
      _connectedDevice = device;
      setState(() {
        _activelyConnectingBool = false;
      });
    }
  }

  Future<void> initSpeechState() async {
    bool hasSpeech = await speech.initialize(
        onError: errorListener, onStatus: statusListener);
    if (hasSpeech) {
      var systemLocale = await speech.systemLocale();
      _currentLocaleId = systemLocale.localeId;
    }

    if (!mounted) return;

    setState(() {});
  }

  void startListening() {
    lastWords = "";
    lastError = "";
    speech.listen(
      onResult: resultListener,
      // listenFor: Duration(seconds: 60),
      // pauseFor: Duration(seconds: 3),
      localeId: _currentLocaleId,
      // onSoundLevelChange: soundLevelListener,
      cancelOnError: true,
      partialResults: true,
      // onDevice: true,
      // listenMode: ListenMode.confirmation,
      // sampleRate: 44100,
    );
    setState(() {});
  }

  void stopListening() {
    speech.stop();
    setState(() {
      level = 0.0;
    });
  }

  void cancelListening() {
    speech.cancel();
    setState(() {
      level = 0.0;
    });
  }

  correctText() {
    List<List<String>> correctionTable = globals.correctionTable;
    for (TextEditingController cont in _controllers) {
      String text = cont.text;
      List<String> words = text.split(' ');
      for (int i = 0; i < words.length; i++) {
        String word = words[i];
        String compare = word;

        if (equalsIgnoreCase('insert', word)) {
          if (i < word.length - 1){
            words[i] = '.' + words[i + 1] + '/n';
            words.removeAt(i + 1);
          }
        }
        if (compare.endsWith('.')){
          compare = compare.substring(0, compare.length - 1);
        }
        for (List<String> row in correctionTable) {
          String wrong = row[0];
          List<String> wrongWords = wrong.split(' ');

            if (equalsIgnoreCase(word, wrongWords[0])) {
              print('first words match ' + word + wrongWords[0]);
              if (words.sublist(i).length >=  wrongWords.length) {
                print('has enough length' + (words.sublist(i).length - 1).toString() + wrongWords.length.toString());
                String compareText = words.sublist(i, i + wrongWords.length ).join(' ');
                bool hasDot = false;

                compareText = compareText.replaceAll('.', '');
                print('compare text: ' + compareText);
                if (equalsIgnoreCase(compareText, wrong)) {
                  for (int r in range(0, wrongWords.length - 1)) {
                    words.removeAt(i);
                  }
                  words[i] = row[1];

                }

              }
            }
        }
      }

      cont.text = words.join(' ');

    }
  }

  List<String> frozen = List<String>();

  void resultListener(SpeechRecognitionResult result) {
    setState(() {
      lastWords = "${result.recognizedWords}";

      parseWords(lastWords);

      if (result.finalResult) {

        correctText();

        if (_controllers[currentSection]
            .text
            .substring(_controllers[currentSection].text.length - 1) !=
            ".") {
          print('here' + _controllers[currentSection]
              .text
              .substring(_controllers[currentSection].text.length ));
          _controllers[currentSection].text =
              _controllers[currentSection].text + ".";

        }
      }
    });
  }

  parseWords(String string) {
    List<int> indicesOfString = List<int>();
    List<int> mentionedSections = List<int>();
    List<String> words = string.split(" ");
    for (String word in words) {
      ////Search for index of sections words
      for (var i = 0; i < _sections.length; i++) {
        if (equalsIgnoreCase(word, _keyWords[i])) {
          print(word.indexOf(word).toString() +
              i.toString() +
              currentSection.toString());

          currentSection = i;
          int keyOpen = 0;
          for (var k = 0; k < currentSection; k++) {
            if (_sections[k].substring(0, 1) != '*') {
              keyOpen++;
              print('key' + keyOpen.toString());
            }
          }

          for (var i = 0; i < keyStack.length; i++) {
            if (i == keyOpen) {
              print('keyopening' + i.toString());
              keyStack[i].currentState.setActive();
              keyStack[i].currentState.setState(() {});
            } else {
              print('closing' + i.toString());
              keyStack[i].currentState.setInactive();
              keyStack[i].currentState.setState(() {});
            }
          }
          keyStack[keyOpen].currentState.expand();
          indicesOfString.add(words.indexOf(word));
          mentionedSections.add(i);
        }
        ;
      }
      ;
    }
    ;
    print(indicesOfString.length);
    print('current section: ' +
        currentSection.toString() +
        indicesOfString.length.toString());

    if (indicesOfString.length == 0 &&
        currentSection != null &&
        words.length > 1) {
      indicesOfString.add(-1);
      mentionedSections.add(currentSection);
    }
    print( _keyWords);
    print(indicesOfString);

    List<String> chunk;
    if (_sections.contains('Presents')) {
      if (_controllers[_sections.indexOf('Presents')].text == '') {
        chunk = words;
        chunk.asMap().forEach((key, value) {
          if (equalsIgnoreCase(value, "new")) {
            if (key < chunk.length - 1) {
              if (equalsIgnoreCase(chunk[key + 1], "patient")) {
                _controllers[_sections.indexOf('Presents')].text = 'new';
              }
            }
          }
        });
        chunk.asMap().forEach((key, value) {
          if (equalsIgnoreCase(value, "established")) {
            if (key < chunk.length - 1) {
              if (equalsIgnoreCase(chunk[key + 1], "patient")) {
                _controllers[_sections.indexOf('Presents')].text =
                    'established';
              }
            }
          }
        });
      }
    }
    if (indicesOfString.length > 0) {
      for (var j = 0; j < indicesOfString.length; j++) {
        if (j == indicesOfString.length - 1) {
          if (indicesOfString[j] < words.length) {
            chunk = words.sublist(indicesOfString[j] + 1);
          }
        } else {
          if (indicesOfString[j] < words.length) {
            chunk =
                words.sublist(indicesOfString[j] + 1, indicesOfString[j + 1]);
          }
        }
        print('here');

        if (_sections[mentionedSections[j]] == 'Exam') {
          List<int> insert = List<int>();
          chunk.asMap().forEach((key, value) {
            if (equalsIgnoreCase(value, "On")) {
              if (key < chunk.length - 2){
                if (equalsIgnoreCase(chunk[key + 1], 'the')){
                  if (key - 1 >= 0){
                    insert.add(key);
                  }
                }
              }
            }
          });
          for (int i = insert.length; i > 0; i--){
            chunk.insert(insert[i - 1], '\n');
          }
        }

        var combined = chunk.join(" ");

        // print('space end ' + frozen[mentionedSections[j]].substring(frozen[mentionedSections[j]].length - 1));
        if (frozen[mentionedSections[j]].length > 2) {
          if (frozen[mentionedSections[j]].substring(frozen[mentionedSections[j]].length - 1) != ' ') {
            frozen[mentionedSections[j]] = frozen[mentionedSections[j]] + ' ';
          }
        }
        _controllers[mentionedSections[j]].text =
            frozen[mentionedSections[j]] + combined;
      }
    }
  }

  void soundLevelListener(double level) {
    minSoundLevel = min(minSoundLevel, level);
    maxSoundLevel = max(maxSoundLevel, level);
    // print("sound level $level: $minSoundLevel - $maxSoundLevel ");
    setState(() {
      this.level = level;
    });
  }

  void errorListener(SpeechRecognitionError error) {
    // print("Received error status: $error, listening: ${speech.isListening}");
    setState(() {
      lastError = "${error.errorMsg} - ${error.permanent}";
    });
  }

  void statusListener(String status) {

    setState(() {
      lastStatus = "$status";
      print(status);
      if (status == 'listening') {
        indicatorColor = Theme.of(context).accentColor;
      } else {
        indicatorColor = Colors.grey;
      }
    });
  }

  BluetoothCharacteristic writeCharacteristic;

  List<String> _sections = [
    'Initial Note*.bluenote/n',
    '**F2',
    'Presents',
    '**F2',
    'Complaining',
    '**F2',
    'Exam',
    '**F2',
    'Plan*.dplanaa/n'
  ];
  List<String> _keyWords = [];
  List<Widget> _mainTiles = List<Widget>();
  List<Color> _sectionColors = List<Color>();
  List<GlobalKey<AppExpansionTileState>> keyStack =
      List<GlobalKey<AppExpansionTileState>>();
  List<TextEditingController> _controllers = List<TextEditingController>();

  SingleChildScrollView _buildConnectDeviceView() {
    List<Container> containers = new List<Container>();
    if (_mainTiles.length == 0) {
      updateSectionContents();
    }

    return SingleChildScrollView(
      child: Column(
        children: <Widget>[..._mainTiles],
      ),
    );
  }


  updateSectionContents() {

    setState(() {
      print('updating contents');
      keyStack = List<GlobalKey<AppExpansionTileState>>();
      _controllers = List<TextEditingController>();
      _mainTiles = List<Widget>();
      _sectionColors = List<Color>();
      _keyWords = List<String>();
      for (var i = 0; i < _sections.length; i++) {
        frozen.add('');
        _sectionColors.add(Colors.transparent);
        if (_sections[i].contains('*')){
          _keyWords.add(_sections[i].substring(0, _sections[i].indexOf('*')));
        }else{
          _keyWords.add(_sections[i]);
        }

        print(_sections[i]);
        if (_sections[i].length < 2) {
          _sections[i] = '  ';
        }
        if (_sections[i].substring(0, 2) == "**") {
          TextEditingController addControler = new TextEditingController();
          String rest = _sections[i].substring(2);
          List<String> keys = rest.split(',');
          addControler.text = "";
          for (String key in keys) {
            if (key == 'F2') {
              addControler.text =
                  addControler.text + "/195"; //f195 e176 t179 u218 d217
            } else if (key == 'enter') {
              addControler.text = addControler.text + "/176";
            } else if (key == 'tab') {
              addControler.text = addControler.text + '/179';
            } else if (key == 'up') {
              addControler.text = addControler.text + '/218';
            } else if (key == 'down') {
              addControler.text = addControler.text + '/217';
            } else if (key == 'back') {
              addControler.text = addControler.text + '/178';
            } else if (key == 'alt') {
              addControler.text = addControler.text + '/130';
            }
          }
          _controllers.add(addControler);

          List<Widget> keyBits = <Widget>[
            Text("   "),
            Icon(FlutterIcons.keyboard_o_faw),
            VerticalDivider(),
          ];
          for (String key in keys) {
            keyBits.add(Text(key));
            keyBits.add(VerticalDivider());
          }
          Container addTile = Container(
            child: Row(
              children: keyBits,
            ), //Text('F2',),
          );
          _mainTiles.add(addTile);
        } else {
          TextEditingController addControler = new TextEditingController();
          _controllers.add(addControler);
          String title = _sections[i];
          if (_sections[i].contains('*')) {
            if (title.indexOf('*') + 1 < title.length) {
              addControler.text = title.substring(title.indexOf('*') + 1);
            }
            title = title.substring(0, title.indexOf('*'));
          }
          final GlobalKey<AppExpansionTileState> key1 = new GlobalKey();
          keyStack.add(key1);
          List<Widget> options = List<Widget>();
          if (equalsIgnoreCase(title, 'presents')) {
            options = [
              VerticalDivider(),
              RaisedButton(
                child: Text('New'),
                onPressed: () => {
                  _controllers[i].text = 'new',
                  keyStack[_getKeyIndex(i)].currentState.setActive(),
                  keyStack[_getKeyIndex(i)].currentState.expand(),
                  keyStack[_getKeyIndex(i)].currentState.setState(() {}),
                },
              ),
              VerticalDivider(),
              RaisedButton(
                child: Text('Established'),
                onPressed: () => {
                  _controllers[i].text = 'established',
                  keyStack[_getKeyIndex(i)].currentState.setActive(),
                  keyStack[_getKeyIndex(i)].currentState.expand(),
                  keyStack[_getKeyIndex(i)].currentState.setState(() {}),
                },
              )
            ];
          }
          AppExpansionTile addTile = AppExpansionTile(
              key: key1,
              title: Row(
                children: <Widget>[
                      Text(
                        title,
                      ),
                    ] +
                    options,
              ),
              backgroundColor: _sectionColors[i],
              children: <Widget>[
                new ListTile(
                  title: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              keyboardType: TextInputType.text,
                              maxLines: null,
                              controller: addControler,
                              onTap: () => {
                                print('tapped'),
                                if (!editing){
                                  print('start editing'),
                                  editing = true,
                                  beforeEdit = addControler.text,
                                }
                              },
                              onEditingComplete: () => {
                                print('done editing'),
                                editing = false,
                                FocusScope.of(context).unfocus(),
                                afterEdit = addControler.text,
                                rememberCorrection(),
                              },
                            ),
                          ),
                          Container(
                            height: 50,
                            child: FittedBox(
                              fit: BoxFit.fitWidth,
                              child: IconButton(

                                onPressed: () =>
                                    {addControler.text = "", frozen[i] = ""},
                                icon: Icon(
                                  Icons.delete_forever,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ]);
          _mainTiles.add(addTile);
        }
      }
    });
  }
  bool editing = false;

  rememberCorrection() {
    print('starting remember correction');
    if (beforeEdit.contains('.')){
      beforeEdit = beforeEdit.replaceAll('.', '');
    }
    List<String> before = beforeEdit.split(' ');
    before.removeWhere((element) =>  element == '');
    if (afterEdit.contains('.')){
      afterEdit = afterEdit.replaceAll('.', '');
    }
    List<String> after = afterEdit.split(' ');
    after.removeWhere((element) =>  element == '');

    int diffCount = 0;

    print('differences');
    print(diff(afterEdit, beforeEdit, )  );
    List<Diff> diffs = diff(afterEdit, beforeEdit, );
    String b = '';
    String bbefore = '';
    String bafter = '';
    String a = '';

    diffs.asMap().forEach((key, value) {
      if (diffs.length > 1) {
        if (key == 0) {
          bbefore = value.text;
        }

        if (key == diffs.length - 1) {
          if (value.operation == 0){
            bafter = value.text;
          }else if (value.operation == 1){
            a = a + value.text;
          }else if (value.operation == -1) {
            b = b + value.text;
          }

        }

        if (key != 0 && key != diffs.length - 1) {
          if (value.operation == 0 || value.operation == -1) {
            b = b + value.text;
          }
          if (value.operation == 0 || value.operation == 1) {
            a = a + value.text;
          }
        }

      }
    });

    if (before.length > 0) {
      if (bbefore.substring(bbefore.length - 1) !=  ' ' && bbefore.substring(bbefore.length - 1) !=  '.') {
        print('last letter not space, adding: ' + bbefore.substring(bbefore.lastIndexOf(' ')));
        a = bbefore.substring(bbefore.lastIndexOf(' ') + 1) + a;
        b = bbefore.substring(bbefore.lastIndexOf(' ') + 1) + b;
      }
    }
    if (bafter.length > 0) {
      if (bafter.substring(0, 1) !=  ' ' && bafter.substring(0, 1) !=  '.') {
        print('first letter not space, adding: ' + bafter.substring(0, bafter.indexOf(' ')));
        a =  a + bafter.substring(0, bafter.indexOf(' ') );
        b = b + bafter.substring(0, bafter.indexOf(' ') ) ;
      }
    }

    print('a,b|' + a + '|' + b);
    if (a.length > 2 && b.length > 2 && a.length < 30 && b.length < 30 ) {
      toAdd = a + ' = ' + b;
      badgeShow = true;
      startBadgeFade();
    }

  }
  Timer badgeFadeTimer;
  int countDown = 0;
  startBadgeFade() {
    countDown =  0;
    badgeFadeTimer = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      countDown++;
      if (countDown > 3 ) {
        badgeFadeTimer.cancel();
        setState(() {
          badgeShow = false;
        });
      }
    });
  }


  _getKeyIndex(int current) {
    int currentSection = current;
    int keyOpen = 0;
    for (var k = 0; k < currentSection; k++) {
      if (_sections[k].substring(0, 1) != '*') {
        keyOpen++;
        print('key' + keyOpen.toString());
      }
    }
    return keyOpen;
  }

  _collapseAll() {
    for (GlobalKey<AppExpansionTileState> key in keyStack) {
      if (key.currentState != null) {
        key.currentState.collapse();
      }
    }
  }

  _expandAll() {
    print(keyStack);
    for (GlobalKey<AppExpansionTileState> key in keyStack) {
      if (key.currentState != null) {
        key.currentState.expand();
      }
    }
  }

  int currentSection;

  Color speakingColor = Colors.indigoAccent;

  List<String> shorts = [
    'vickerc1**tab**1qaz@WSX1qaz@WSX**enter**',
    'vickerc1**tab**1qaz@WSX1qaz@WSX**enter,enter**'
  ];
  List<TextEditingController> shortControllers = List<TextEditingController>();
  bool editingShorts = false;

  getShortParts(String string) {
    List<Widget> parts = List<Widget>();
    List<String> starSplit = string.split('**');
    for (int i = 0; i < starSplit.length; i++) {
      if (i.isEven) {
        parts.add(
          Text(
            starSplit[i],
            textAlign: TextAlign.center,
          ),
        );
        parts.add(VerticalDivider());
      } else {
        parts.add(Icon(FlutterIcons.keyboard_o_faw));
        parts.add(VerticalDivider());
        List<String> keys = starSplit[i].split(",");
        for (String key in keys) {
          parts.add(Text(key));
          parts.add(VerticalDivider());
        }
      }
    }
    return Wrap(
      children: parts,
    );
  }

  List<Widget> shortTiles = List<Widget>();
  _epicLogin() async {
    
    print('start open');
    List<Widget> children = [];
    shortControllers = List<TextEditingController>();
    if (!editingShorts) {
      for (String row in shorts) {
        children.add(ListTile(
          title: Text(row),
          subtitle: getShortParts(row),
          onTap: () => {
            Navigator.pop(context),
            _sendShort(row),
          },
        ));
        children.add(Divider());
      }
      children.add(RaisedButton(
        child: Text('edit'),
        onPressed: () => {
          setState(() => {
                editingShorts = true,

                _epicLogin(),
              })
        },
      ));
    } else {
//      for (String row in shorts) {
      shorts.asMap().forEach((key, row) {
        TextEditingController add = TextEditingController();
        shortControllers.add(add);
        add.text = row;
        children.add(ListTile(
          title: TextField(
            maxLines: null,
            controller: add,
            keyboardType: TextInputType.text,
            onChanged: (string) => {
              shorts[key] = string,
            },
          ),
          trailing: IconButton(
            onPressed: () => {
              Navigator.pop(context),
              FocusScope.of(context).unfocus(),
              shorts.removeAt(shorts.indexOf(row)),
              _epicLogin(),
            },
            icon: Icon(
              FlutterIcons.delete_ant,
            ),
          ),
        ));
        children.add(Divider());
      });
      children.add(Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            RaisedButton(
              child: Text('done'),
              onPressed: () => {
                setState(() => {
                      editingShorts = false,

                      _savePreferences(),

                      _epicLogin(),
                    })
              },
            ),
            RaisedButton(
              child: Text('add'),
              onPressed: () => {
                setState(() => {
                      shorts.add(''),

                      _epicLogin(),
                    })
              },
            ),
          ]));
    }
    shortTiles = children;

    // openRightDrawer();

  }

  _bleButtonIcon() {
    if (_connectedDevice == null) {
      if (_activelyConnectingBool) {
        return Padding(
          padding: EdgeInsets.all(15),
          child: FittedBox(
            child: SpinKitWave(
              color: Theme.of(context).accentColor,
              itemCount: 10,
              type: SpinKitWaveType.center,
              duration: Duration(milliseconds: 2000),
            ),
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 0, horizontal: 15),
        child: IconButton(
          onPressed: scanAndConnectDefault,
          icon: Icon(
            FlutterIcons.search1_ant,
            color: Colors.grey,
          ),
        ),
      );
    }
    if (_activelyConnectingBool) {
      return Padding(
        padding: EdgeInsets.all(15),
        child: FittedBox(
          child: SpinKitWave(
            color: Colors.white,
            itemCount: 10,
            type: SpinKitWaveType.center,
            duration: Duration(milliseconds: 2000),
          ),
        ),
      );
    } else {
      return Padding(
          padding: EdgeInsets.symmetric(vertical: 0, horizontal: 15),
          child: Icon(
            FlutterIcons.check_square_faw,
          ));
    }
  }

  bool _activelyConnectingBool = true;

  bool editingSections = false;
  List<String> oldSections;

  toggleEdit() {
    setState(() {
      editingSections = !editingSections;
      if (editingSections) {
        print('save old section');
        oldSections = List.from(_sections);
      }
    });
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    // For your reference print the AppDoc directory
    print(directory.path);
    return directory.path;
  }

  List<Widget> tiles = List<Widget>();
  openFiles() async {
    print('start folder bit');
    String lp = await _localPath;
    List<String> files = [];
    List<FileSystemEntity> fileDetails = [];
    Directory.fromUri(Uri.file(lp))
        .list(recursive: true, followLinks: false)
        .listen((FileSystemEntity entity) {
      print('this path:  ' + entity.path);
      files.add(entity.path);
      fileDetails.add(entity);
    }).onDone(() {
      print("found files: " + files.toString());
      tiles = List<Widget>();
      if (files.length > 0) {
        tiles.add(IconButton(
          iconSize: 100,
          icon: Icon(
            FlutterIcons.add_circle_mdi,
            color: Theme.of(context).accentColor,
          ),
          onPressed: () => {
            _saveCurrentFile(),
            _loadPreferences(),
            _clearAll(),
            currentFileName = null,
            Navigator.pop(context),
          },
        ));

        for (int i = 0; i < files.length; i++) {
          String e = files[i];
          Color fileHighlight = Theme.of(context).primaryColor;
          if (e.substring(e.lastIndexOf('/') + 1, e.lastIndexOf('.')) ==
              currentFileName) {
            fileHighlight = Theme.of(context).primaryColor.withAlpha(100);
          }
          String uncut;
          List<String> cut;
          tiles.add(
            Center(
              child: Container(
                padding: EdgeInsets.all(15),
                child: GestureDetector(
                  onTap: () => {
                    currentFileName =
                        e.substring(e.lastIndexOf('/') + 1, e.lastIndexOf('.')),
                    Navigator.pop(context),
                    uncut = File(e).readAsStringSync(),
                    print('uncut ' + uncut),
                    cut = uncut.split('_'),
                    cut.removeLast(),
                    _sections = [],
                    _keyWords = [],
                    for (int i = 0; i < cut.length; i++)
                      {

                        _sections.add(cut[i]),
                        print('added section: ' + cut[i]),
                        if (cut[i].contains('*')){
                          print('contains at ' + cut.indexOf('*').toString()),
                          _keyWords.add(cut[i].substring(0,cut[i].indexOf('*'))),
                        }else{
                          print('no contain'),
                          _keyWords.add(cut[i]),
                        },
                        print(cut[i]),

                      },
                    updateSectionContents(),
                  },
                  child: Container(
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(15)),
                      border: Border.all(width: 2, color: Colors.black),
                      color: fileHighlight,
                    ),
                    child: Column(
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                e.substring(
                                    e.lastIndexOf('/') + 1, e.lastIndexOf('.')),
                                maxLines: null,
                                overflow: TextOverflow.fade,
                              ),
                            ),
                            CircleAvatar(
                              backgroundColor: Theme.of(context).accentColor,
                              child: IconButton(
                                icon: Icon(
                                  FlutterIcons.delete_ant,

                                ),
                                onPressed: () => {
                                  print('deleting' + e),
                                  File(e).delete(),
                                  openFiles(),
                                  setState(() => {}),
                                },
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                File(e).lastModifiedSync().toString(),
                                maxLines: 5,
                                overflow: TextOverflow.fade,
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    });
  }
  Widget fileView() {
    return Container(
      child: Column(

        children: [
          Container(
            alignment: Alignment.centerRight,
            height: 50,
            child: Row(
              children: [
                Expanded(
                  child: Container(),
                ),
                Container(
                  color: Theme.of(context).accentColor,
                  child: GestureDetector(
                    child: Row(

                      children: [
                        VerticalDivider(),
                        Text('delete all  ', style: TextStyle(
                          color: Theme.of(context).primaryColor,
                        ),),

                        Icon(FlutterIcons.delete_sweep_mco,
                          color: Theme.of(context).primaryColor,
                        ),
                      ],
                    ),
                    onTap: deleteAllFiles,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              children: tiles,
            ),
          ),
        ],
      ),
    );
  }

  deleteAllFiles() async {
    print('deleting all');
    String lp = await _localPath;
    List<String> files = [];
    List<FileSystemEntity> fileDetails = [];
    Directory.fromUri(Uri.file(lp))
        .list(recursive: true, followLinks: false)
        .listen((FileSystemEntity entity) {
      print('this path:  ' + entity.path);
      files.add(entity.path);
      fileDetails.add(entity);
    }).onDone(() {
      for (String path in files) {
        File(path).delete();
      }
      openFiles();
      setState(() {

      });
    });
  }

  _nameFile() {
    print(currentFileName);
    if (currentFileName == null || currentFileName == 'Untitled') {
      if (_sections.contains('Complaining')) {
        print(_sections.indexOf('Complaining'));
        if (_controllers[_sections.indexOf('Complaining')].text != '') {
          List<String> words =
              _controllers[_sections.indexOf('Complaining')].text.split(' ');
          if (words.length > 1) {
            if (equalsIgnoreCase('of', words.first)) {
              words.removeAt(0);
            } else {}
            ;
            if (words.length > 5) {
              words = words.sublist(0, 5);
            }
          }
          currentFileName = words.join('_');

          currentFileName = currentFileName.replaceAll('.', '');
        } else {
          currentFileName = 'Untitled';
        }
        print('named ' + currentFileName);
      } else {
        currentFileName = 'Untitled';
      }
    }
  }

  _saveCurrentFile() async {
    _nameFile();
    print('start save');
    String toBeSaved = '';
    for (int i = 0; i < _sections.length; i++) {
      toBeSaved = toBeSaved + _sections[i];
      if (_sections[i].substring(0, 2) == '**') {
      } else if (_sections[i].contains('*')) {
        toBeSaved = toBeSaved.substring(0, toBeSaved.lastIndexOf('*') + 1) +
            _controllers[i].text;
      } else {
        if (_controllers[i].text != '') {
          toBeSaved = toBeSaved + '*' + _controllers[i].text;
        }
      }
      toBeSaved = toBeSaved + '_';
    }
    print('to be saved ' + toBeSaved);
    Directory directory = await getApplicationDocumentsDirectory();
    File(directory.path + "/" + currentFileName + '.txt')
        .writeAsString(toBeSaved);
    print('saved ' + directory.path + "/" + currentFileName + '.txt');
  }

  Widget _buttonAction() {
    if (showSpecialKeys) {
      return Expanded(
        flex: 100,
        child: Container(
            padding: EdgeInsets.all(15),
            child: Stack(alignment: Alignment.bottomCenter,
//                    verticalDirection: VerticalDirection.up,
                children: <Widget>[
                Container(

                  child: TextField(
                    autofocus: true,
                    focusNode: _nodeText6,
                    keyboardType: TextInputType.text,
                    controller: instaController,
                    onChanged: (string) => {
                      if (writeCharacteristic != null)
                        {
                          writeCharacteristic
                              .write(utf8.encode(instaController.text)),
                          instaController.text = '',
                        }
                    },
                    onSubmitted: (string) => {
                      setState(() => {
                            print('done editing'),
                            resizeScaffold = false,
                            showSpecialKeys = false,
                          })
                    },
                  )),
                  Container(
                      decoration: BoxDecoration(
                          color: Theme.of(context).accentColor.withAlpha(100),
                          borderRadius: BorderRadius.all(Radius.circular(15))),
                      child: specialKeys()),
                ])),
      );
    }

    return Container(
      child: Padding(
        padding: EdgeInsets.all(15),
        child: Column(
          verticalDirection: VerticalDirection.up,
          children: <Widget>[
            Container(
              height: 200,
              decoration: BoxDecoration(
                  color: Theme.of(context).accentColor.withAlpha(100),
                  borderRadius: BorderRadius.all(Radius.circular(15))),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(5),
                              child: FittedBox(
                                alignment: Alignment.center,
                                child: Stack(
                                  children: <Widget>[
                                    IconButton(

                                      onPressed: toggleEdit,
                                      icon: Icon(FlutterIcons.edit_2_fea),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(5),
                              child: FittedBox(
                                child: IconButton(

                                  onPressed: () => {
                                    _saveCurrentFile(),
                                    openFiles(),
                                  },
                                  icon: Icon(
                                    FlutterIcons.folder1_ant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(5),
                              child: FittedBox(
                                child: IconButton(

                                  onPressed: _epicLogin,
                                  icon: Icon(
                                    FlutterIcons.wi_lightning_wea,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]),
                  ),
                  Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(5),
                              child: FittedBox(
                                child: IconButton(

                                  onPressed: _sendBox,
                                  icon: Icon(
                                    sendIcon,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(5),
                              child: FittedBox(
                                child: IconButton(

                                  onPressed: _allColEx,
                                  icon: Icon(
                                    colOrExIcon,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(5),
                              child: FittedBox(
                                child: IconButton(

                                  onPressed: _clearAll,
                                  icon: Icon(
                                    FlutterIcons.redo_alt_faw5s,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]),
                  ),
                  Expanded(
                    flex: 3,
                    child: Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.all(15),
                      child: GestureDetector(
                        onTapDown: (details) => {
                          if (lockListen)
                            {
                              unlockListen(),

                            }
                          else
                            {
                              Vibration.vibrate(duration: 2000),
                              print('down press'),
                              indicatorColor = Colors.grey,
                              for (var i = 0; i < _controllers.length; i++)
                                {
                                  frozen[i] = _controllers[i].text,
                                },
                              print(frozen),
                              lockListen = true,
                              startListening(),
                              setState(() => {
                                listenTimeLeft = 1,
                                micIcon = FlutterIcons.lock_ant,
                              }),
                              lockTimeout =
                                  Timer.periodic(Duration(seconds: 1), (timer) {
                                    updateTimout();
                                  })
                            }
                        },
                        onVerticalDragUpdate: (details) => {
                          print('drag' + details.localPosition.dy.toString()),
                          if (details.localPosition.dy < 40)
                            {
                              print('locked'),
                              lockListen = true,
                            }
                          else
                            {
                              lockListen = false,
                            }
                        },
                        onVerticalDragEnd: (details) => {
                          print(' drag ended'),
                          if (lockListen)
                            {
                              print('currently locked'),
                              setState(() => {
                                    listenTimeLeft = 1,
                                    micIcon = FlutterIcons.lock_ant,
                                  }),
                              lockTimeout =
                                  Timer.periodic(Duration(seconds: 1), (timer) {
                                updateTimout();
                              })
                            }
                          else
                            {stopListening()}
                        },
                        onTapUp: (details) => {
                          print('up press'),
                          if (lockListen)
                            {
                              print('locked'),
                            }
                          else
                            {stopListening()}
                        },
                        child: Container(
                          alignment: Alignment.center,
                          padding: EdgeInsets.all(25),
                          child: FittedBox(
                            alignment: Alignment.center,
                            fit: BoxFit.fitWidth,
                            child: Stack(
                              alignment: Alignment.center,
                              children: <Widget>[
                                Icon(
                                  micIcon,
                                  size: 40,

                                ),
                                CircularPercentIndicator(
                                  percent: listenTimeLeft,
                                  radius: 100,
                                  progressColor: Theme.of(context).accentColor,
                                  animateFromLastPercent: true,
                                  animation: true,
                                  animationDuration: listenAnimationDuration,
                                ),
                              ],
                            ),
                          ),
                          decoration: BoxDecoration(
                            color: indicatorColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }

  updateTimout() {
    setState(() {
      secondsOfLockLeft--;
      listenTimeLeft = secondsOfLockLeft / 60;
      if (secondsOfLockLeft < 1) {
        unlockListen();
      }
    });
  }

  unlockListen() {
    lockListen = false;
    setState(() {
      micIcon = FlutterIcons.mic_ent;
      secondsOfLockLeft = 59;
      listenTimeLeft = 0;
      lockTimeout.cancel();
      if (speech.isListening) {
        speech.stop();
      }
    });
  }

  bool lockListen = false;
  int secondsOfLockLeft = 60;
  double listenTimeLeft = 0;
  int listenAnimationDuration = 1000;
  IconData micIcon = FlutterIcons.mic_ent;

  _clearAll() {
    for (var i = 1; i < _controllers.length; i++) {
      _controllers[i].text = '';
      frozen[i] = '';
    }
    updateSectionContents();
    currentSection = null;
  }

  _allColEx() {
    keyStack.forEach((element) {
      print(element.currentState);
    });
    setState(() {
      if (keyStack[0].currentState._isExpanded) {
        colOrExIcon = FlutterIcons.arrow_expand_vertical_mco;
        _collapseAll();
      } else {
        colOrExIcon = FlutterIcons.arrow_collapse_vertical_mco;
        _expandAll();
      }
    });
  }

  IconData colOrExIcon = FlutterIcons.arrow_expand_vertical_mco;

  static final myController = TextEditingController();
  var toSendTest = (TextFormField(
    controller: myController,
    decoration: InputDecoration(labelText: 'to send'),
  ));

  bool completedSending = true;
  bool clearForSending = true;

  IconData sendIcon = FlutterIcons.rocket_ent;

  getASCII(String key){
    String ascii = '';
    if (key == 'F2') {
      ascii  = "/195"; //f195 e176 t179 u218 d217
    } else if (key == 'enter') {
      ascii  = "/176";
    } else if (key == 'tab') {
      ascii  = '/179';
    } else if (key == 'up') {
      ascii  = '/218';
    } else if (key == 'down') {
      ascii  = '/217';
    } else if (key == 'back') {
      ascii  = '/178';
    } else if (key == 'alt') {
      ascii  = '/130';
    }
    return ascii;
  }
  double specialKey = 200;
  _sendShort(String string) async {
    print('short' + string);
    if (writeCharacteristic != null) {
      List<String> expandedSplit = List<String>();
      List<String> starSplit = string.split('**');
      for (int i = 0; i < starSplit.length; i++) {
        if (i.isEven) {
          expandedSplit.add(starSplit[i]);
        } else {
          List<String> keys = starSplit[i].split(",");
          for (String key in keys) {
            expandedSplit.add(getASCII(key));
          }
        }
      }


      bool specialBool = false;
      for (String row in expandedSplit) {
        if (row[0] == '/') {
          specialBool = true;
        }else{
          specialBool = false;
        }
        List<String> stack = List<String>();
        String data = row;
        print((data.length / 20).floor());
        if (data.length > 20) {
          for (var i = 0; i < ((data.length / 20).floor() + 1); i++) {
            print(i);
            if (i != (data.length / 20).floor()) {
              print('not end');
              print(data.substring(20 * i, 20 * i + 20).toString());
              stack.add(data.substring(20 * i, 20 * i + 20).toString());
              print(stack);
            } else {
              print(data.substring(20 * i).toString());
              stack.add(data.substring(20 * i));
              print(stack);
            }
          }
        } else {
          print('not greater than 20');
        }
        print(stack);
        if (stack.length > 0) {
          print('long stack');
          for (var i = 0; i < stack.length; i++) {
            if (!clearForSending) {
              break;
            }

            writeCharacteristic.write(utf8.encode(stack[i]));

            if (specialBool) {
              await Future.delayed(Duration(milliseconds: specialKey.toInt()));
            }
            await Future.delayed(Duration(milliseconds: delaySliderValue.round()));
          }
        } else {
          print('short stack');

          writeCharacteristic.write(utf8.encode(data));

          if (specialBool) {
            await Future.delayed(Duration(milliseconds: specialKey.toInt()));
          }
          await Future.delayed(Duration(milliseconds: delaySliderValue.round()));
        }
      }
    }
  }

  flip() async {
    setState(() {
      showWaiting = !showWaiting;
    });
  }
  stopBLE() {
    clearForSending = false;
    completedSending = true;
  }

  _sendBox() async {
    print('send pressed');
    clearForSending = true;
    if (completedSending) {
      if (writeCharacteristic != null) {
        flip();
        completedSending = false;
        print('sending some data over');
        String data = "";
        for (TextEditingController cont in _controllers)  {
          if (!clearForSending) {
            break;
          }
          print('to add:' +
              cont.value.text.toString() +
              "//" +
              cont.text.toString());
          String data = cont.value.text.toString();
          if (cont.value.text.contains('\n') == true) {
            print('has enter: ' + cont.value.text.indexOf('\n').toString());

            data = data.replaceAll('\n', '/n');
            print(data);
          };
          List<String> stack = List<String>();
          print((data.length / 20).floor());
          if (data.length > 20) {
            for (var i = 0; i < ((data.length / 20).floor() + 1); i++) {
              print(i);
              if (i != (data.length / 20).floor()) {
                print('not end');
                print(data.substring(20 * i, 20 * i + 20).toString());
                stack.add(data.substring(20 * i, 20 * i + 20).toString());
                print(stack);
              } else {
                print(data.substring(20 * i).toString());
                stack.add(data.substring(20 * i));

                print(stack);
              }
            }
          } else {
            print('not greater than 20');
          }
          print(stack);
          if (stack.length > 0) {
            print('long stack');
            for (var i = 0; i < stack.length; i++) {
              if (!clearForSending) {
                break;
              }
              await writeCharacteristic.write(utf8.encode(stack[i]));
              await Future.delayed(Duration(milliseconds: delaySliderValue.round()));
            }
          } else {
            if (!clearForSending) {
              break;
            }
            print('short stack');
            await writeCharacteristic.write(utf8.encode(data));
            await Future.delayed(Duration(milliseconds: delaySliderValue.round()));
          }
        }
        print('all done sending');
        completedSending = true;
        flip();
      } else {
        print('couldnt find characteristic');
      }
    } else {
      print('abort sending sending');
      clearForSending = false;
      setState(() {
        completedSending = true;

        sendIcon = FlutterIcons.rocket_ent;
      });
    }
  }

  Expanded _decideBody() {
    return Expanded(
      child: _buildConnectDeviceView(),
    );
  }

  _savePreferences() async {
    print('saving...');
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble("Delay", delaySliderValue);
    String toBeSaved = '';
    for (int i = 0; i < _sections.length; i++) {
      toBeSaved = toBeSaved + _sections[i];
      if (_sections[i].substring(0, 2) == '**') {
      } else if (_sections[i].contains('*')) {
        toBeSaved = toBeSaved.substring(0, toBeSaved.lastIndexOf('*') + 1) +
            _controllers[i].text;
      } else {
        if (_controllers[i].text != '') {
          toBeSaved = toBeSaved + '*' + _controllers[i].text;
        }
      }
      toBeSaved = toBeSaved + '_';
    }
    await prefs.setString('savedNote', toBeSaved);
    print('note template to be saved: ' + toBeSaved);
    String shortsSaved = '';
    shorts.asMap().forEach((key, value) {
      shortsSaved = shortsSaved + value + '_';
    });
    print('saving shorts: ' + shortsSaved);
    await prefs.setString('shorts', shortsSaved);
  }

  _loadPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    delaySliderValue = await prefs.getDouble("Delay") ?? 150;

    String shortTemp = await prefs.getString('shorts') ?? "";
    print('loaded shorts: ' + shortTemp);
    if (shortTemp != "") {
      shorts = shortTemp.split('_');
      shorts.removeLast();
    }

    String temp = await prefs.getString('savedNote') ?? "";
    List<String> sections = temp.split('_');
    print("saved template: " + sections.toString());
    sections.removeLast();
    print(_sections);
    setState(() {
      _sections = sections;
    });
    updateSectionContents();
    _epicLogin();

  }

  drawerOpen() {}

  disposeDrawer() {}

  double delaySliderValue = 0;

  Widget noteName;
  bool editNoteName = false;

  TextEditingController instaController = TextEditingController();

  final FocusNode _nodeText6 = FocusNode();

  addLastCorrection() {
    List<String> split = toAdd.split(' = ');
    globals.correctionTable.add(split);
    setState(() {
      badgeShow = false;
    });
  }

  openRightDrawer() {
    print('opening');
    setState(() {
      _scaffoldKey.currentState.openEndDrawer();
    });
  }

  String toAdd = '';
  bool first = true;
  bool badgeShow = false;
  BottomNavyBar holdBar;
  bool tabSent = false;
  BottomNavyBar bbar() {
    holdBar = BottomNavyBar(
      selectedIndex: _selectedIndex,
      showElevation: true, // use this to remove appBar's elevation
      onItemSelected: (index) =>
          setState(()  {
            _selectedIndex = index;
            tabSent = true;
            tabCont.animateToPage(index,
                duration: Duration(milliseconds: 300), curve: Curves.ease).then((value) => {
            tabSent = false,
            });

          }),
      items: [
        BottomNavyBarItem(
          icon: Icon(FlutterIcons.run_fast_mco),
          title: Text('Shorts'),
          activeColor: Theme.of(context).accentColor,
        ),
        BottomNavyBarItem(
            icon: Icon(FlutterIcons.edit_ant),
            title: Text('Note'),
            activeColor: Theme.of(context).accentColor
        ),
        BottomNavyBarItem(
            icon: Icon(FlutterIcons.notebook_mco),
            title: Text('Note B'),
            activeColor: Theme.of(context).accentColor
        ),
        BottomNavyBarItem(
            icon: Icon(FlutterIcons.folder_ent),
            title: Text('Files'),
            activeColor: Theme.of(context).accentColor
        ),


      ],
    );
    return holdBar;
  }

  @override
  Widget build(BuildContext context) {


    if (first){
      indicatorColor = Colors.grey;
      first = false;
    }
    noteName = GestureDetector(
      onTap: () => {
        setState(() => {
              editNoteName = !editNoteName,
            })
      },
      child: Container(
        child: Text(currentFileName ?? 'Ludicrous Speed'),
      ),
    );
    if (editNoteName) {
      TextEditingController t = TextEditingController();
      t.text = currentFileName ?? 'Ludicrous Speed';
      noteName = Container(
        decoration:
            BoxDecoration(border: Border.all(color: Colors.white, width: 1)),
        child: TextField(
          controller: t,
          autofocus: true,

          onSubmitted: (string) => {
            setState(() => {
                  currentFileName = string,
                  editNoteName = false,
                  print('done editing name ' + currentFileName),
                }),
          },
        ),
      );
    }
    final drawerHeader = DrawerHeader(
      child: Column(
        children: <Widget>[
          Text(
            'Ludicrous Speed',
            style: TextStyle(fontSize: 30),
          ),
          Text(
            'Settings',
            style: TextStyle(fontSize: 20),
          ),
        ],
      ),
    );
    final drawerItems = ListView(
      children: <Widget>[
        drawerHeader,
        ListTile(
          leading: Text('Delay'),
          title: Slider(
            value: delaySliderValue,
            min: 0.0,
            max: 500,
            divisions: 10,
            label: '${delaySliderValue.round()}',
            onChanged: (double value) {
              setState(() {
                delaySliderValue = value;
              });
            },
          ),
        ),
        ListTile(
          leading: Text('Alt Delay'),
          title: Slider(
            value: specialKey,
            min: 0.0,
            max: 500,
            divisions: 10,
            label: '${specialKey.round()}',
            onChanged: (double value) {
              setState(() {
                specialKey = value;
              });
            },
          ),
        ),
        RaisedButton(
          onPressed: _loadPreferences,
          child: Text(
            'load',
          ),
        ),
        RaisedButton(
          onPressed: _savePreferences,
          child: Text(
            'save',
          ),
        ),
        RaisedButton(
            onPressed: () => {
                  setState(() => {
                        print('pressed'),
                        showSpecialKeys = true,
                        resizeScaffold = true,
                        Navigator.pop(context),
                        focusDude.requestFocus(),
                    _nodeText6.requestFocus(),
                      })
                },
            child: Text('Free type')),
        RaisedButton(
            onPressed: () => {
              Navigator.push(context, MaterialPageRoute(builder: (context) => CorrectionEdit()))
            },
            child: Text('Edit correction table')),
      ],
    );
    String fullNotesString() {
      
      String send = '';
      _controllers.asMap().forEach((key, value) {
        if (value.text.length > 0) {
          if (value.text.substring(0,1) != '/') {
            send = send + '\n\n' + _sections[key] + ":  " + value.text;
          }
        }else{
          // if (_sections[key])
          send = send + '\n\n' + _sections[key] + ":  " ;
        }

      });
      return send;
    }


    return Scaffold(
        resizeToAvoidBottomInset: true,
        key: _scaffoldKey,
        appBar: AppBar(
          title: noteName,
          actions: <Widget>[_bleButtonIcon()],
        ),
        endDrawer: Drawer(
          child: ListView(
            children: shortTiles ,
          ),
        ),
        drawer: Drawer(
          child: drawerItems,
        ),
        bottomNavigationBar:
        bbar(),

        body:
        PageView(
          controller: tabCont,
          onPageChanged: (int) =>
          setState(() => {

            if (!tabSent) {
              print(int),
              _selectedIndex = int,
            }
          }),
          children: [
          ListView(
          children: shortTiles ,
        ),
            Badge(
              showBadge: badgeShow,
              shape: BadgeShape.square,
              borderRadius: 15,
              position: BadgePosition.bottomEnd( bottom: 10, end: 10),
              badgeContent: Container(
                child: Column(
                  children: [

                    Container(
                      child: Row(
                        children: [
                          Container(

                              child: Text(toAdd)),
                          TextButton(
                            child: Text('add'),
                            onPressed: addLastCorrection,
                          )
                        ],
                      ),
                    ),

                  ],
                ),
              ),
              toAnimate: false,
              badgeColor: Theme.of(context).accentColor,
              child: Stack(
                children: <Widget>[
                  Column(children: <Widget>[

                    _decideBody(),
                    IgnorePointer(
                      child: Container(
                        color: Theme.of(context).primaryColor,
                        child: Text(lastWords),
                      ),
                    ),
                    _buttonAction(),
                  ]),
                  editingOverlay(),
                ],
              ),
            ),
            Badge(
              showBadge: badgeShow,
              shape: BadgeShape.square,
              borderRadius: 15,
              position: BadgePosition.bottomEnd( bottom: 10, end: 10),
              badgeContent: Container(
                child: Column(
                  children: [

                    Container(
                      child: Row(
                        children: [
                          Container(

                              child: Text(toAdd)),
                          TextButton(
                            child: Text('add'),
                            onPressed: addLastCorrection,
                          )
                        ],
                      ),
                    ),

                  ],
                ),
              ),
              toAnimate: false,
              badgeColor: Theme.of(context).accentColor,
              child: Stack(
                children: <Widget>[
                  Column(children: <Widget>[

                    Expanded(
                      child: SingleChildScrollView(child: Text(fullNotesString())),
                    ),
                    IgnorePointer(
                      child: Container(
                        color: Theme.of(context).primaryColor,
                        child: Text(lastWords),
                      ),
                    ),
                    _buttonAction(),
                  ]),
                ],
              ),
            ),
            fileView(),
          ],
        ),


        );

  }


  bool showWaiting = false;
  Widget sending() {
    // if (!showWaiting) {
      return Container();
    // }
    // return Center(
    //   child: Expanded(
    //     child: Container(
    //       color: Colors.black54,
    //       child: Column(
    //         mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    //         children: [
    //           Text(
    //             'Go go go go!',
    //             style: TextStyle(
    //               color: Colors.white,
    //             ),
    //           ),
    //           Container(
    //
    //             child: SpinKitFadingCube(
    //               color: Theme.of(context).accentColor,
    //             ),
    //           ),
    //           RaisedButton(
    //             child: Text('Cancel'),
    //             onPressed: stopBLE,
    //           )
    //         ],
    //       ),
    //     ),
    //   ),
    // );
  }

  onReorder(int oldIndex, int newIndex) {
    print('old' + oldSections.toString());
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final String item = _sections.removeAt(oldIndex);
      _sections.insert(newIndex, item);
    });
  }

  int currentSectionEditing;

  editSection(int index) {
    setState(() {
      currentSectionEditing = index;
    });
  }

  doneEditing() {
    setState(() {
      _sections[currentSectionEditing] = editSectionTextController.text;
      currentSectionEditing = null;
    });
  }

  TextEditingController editSectionTextController = TextEditingController();
  bool editingKeyPressSection = false;

  editingOrNah(int index, String item) {
    if (index == currentSectionEditing) {
      editSectionTextController.text = _sections[index];
      if (_sections[index].length < 2) {
        _sections[index] = '  ';
      }
      if (_sections[index].substring(0, 2) == "**") {
        editingKeyPressSection = true;
        List<Widget> rowContents = [
          Icon(
            FlutterIcons.keyboard_o_faw,
            color: Colors.indigoAccent,
          ),
          VerticalDivider()
        ];
        String rest = _sections[index].substring(2);
        List<String> broken = _sections[index].substring(2).split(',');
        for (String key in broken) {
          rowContents.add(
            Text(
              key,
              style: TextStyle(color: Colors.indigoAccent),
            ),
          );
          rowContents.add(VerticalDivider());
        }
        return Row(
          children: rowContents,
        );
      } else {
        editingKeyPressSection = false;
      }
      return TextField(
        autofocus: true,
        controller: editSectionTextController,
        onEditingComplete: doneEditing,
      );
    }
    if (_sections[index].length < 2) {
      _sections[index] = '  ';
    }
    if (_sections[index].substring(0, 2) == "**") {
      List<Widget> rowContents = [
        Icon(FlutterIcons.keyboard_o_faw),
        VerticalDivider()
      ];
      String rest = _sections[index].substring(2);
      List<String> broken = _sections[index].substring(2).split(',');
      for (String key in broken) {
        rowContents.add(Text(key));
        rowContents.add(VerticalDivider());
      }
      return Row(
        children: rowContents,
      );
    }
    return Text(item);
  }

  removeLastKey() {
    print(currentSectionEditing);
    if (currentSectionEditing != null) {
      if (_sections[currentSectionEditing].length < 2) {
        _sections[currentSectionEditing] = '  ';
      }
      if (_sections[currentSectionEditing].substring(0, 2) == '**') {
        setState(() {
          String rest = _sections[currentSectionEditing].substring(2);
          List<String> keys = rest.split(',');

          print(keys);
          if (keys.length > 1) {
            _sections[currentSectionEditing] =
                '**' + keys.sublist(0, keys.length - 1).join(',');
          } else {
            _sections[currentSectionEditing] = '**';
          }
          print(_sections[currentSectionEditing]);
        });
      }
    }
  }

  List<Slidable> editingItems;
  static const menuItems = <String>['Text', 'Keys'];
  final List<PopupMenuItem<String>> _popUpMenuItems = menuItems
      .map(
        (String value) => PopupMenuItem<String>(
          value: value,
          child: Text(value),
        ),
      )
      .toList();

  specialKeys() {
    return Container(
      child: Wrap(
        children: <Widget>[
          RaisedButton(
            child: Text('alt'),
            onPressed: () => {
              if (showSpecialKeys)
                {
                  if (writeCharacteristic != null)
                    {
                      writeCharacteristic.write(utf8.encode('/130')),
                      //f195 e176 t179 u218 d217
                    }
                }
              else
                {
                  setState(() => {
                        if (_sections[currentSectionEditing].length > 2)
                          {
                            _sections[currentSectionEditing] =
                                _sections[currentSectionEditing] + ',',
                          },
                        _sections[currentSectionEditing] =
                            _sections[currentSectionEditing] + 'alt',
                      })
                }
            },
          ),
          RaisedButton(
            child: Text('up'),
            onPressed: () => {
              if (showSpecialKeys)
                {
                  if (writeCharacteristic != null)
                    {
                      writeCharacteristic.write(utf8.encode('/218')),
                      //f195 e176 t179 u218 d217
                    }
                }
              else
                {
                  setState(() => {
                        if (_sections[currentSectionEditing].length > 2)
                          {
                            _sections[currentSectionEditing] =
                                _sections[currentSectionEditing] + ',',
                          },
                        _sections[currentSectionEditing] =
                            _sections[currentSectionEditing] + 'up',
                      })
                }
            },
          ),
          RaisedButton(
              child: Text('down'),
              onPressed: () => {
                    if (showSpecialKeys)
                      {
                        if (writeCharacteristic != null)
                          {
                            writeCharacteristic.write(utf8.encode('/217')),
                            //f195 e176 t179 u218 d217
                          }
                      }
                    else
                      {
                        setState(() => {
                              if (_sections[currentSectionEditing].length > 2)
                                {
                                  _sections[currentSectionEditing] =
                                      _sections[currentSectionEditing] + ',',
                                },
                              _sections[currentSectionEditing] =
                                  _sections[currentSectionEditing] + 'down',
                            })
                      },
                  }),
          RaisedButton(
              child: Text('tab'),
              onPressed: () => {
                    if (showSpecialKeys)
                      {
                        if (writeCharacteristic != null)
                          {
                            writeCharacteristic.write(utf8.encode('/179')),
                            //f195 e176 t179 u218 d217
                          }
                      }
                    else
                      {
                        setState(() => {
                              if (_sections[currentSectionEditing].length > 2)
                                {
                                  _sections[currentSectionEditing] =
                                      _sections[currentSectionEditing] + ',',
                                },
                              _sections[currentSectionEditing] =
                                  _sections[currentSectionEditing] + 'tab',
                            })
                      },
                  }),
          RaisedButton(
              child: Text('F2'),
              onPressed: () => {
                    if (showSpecialKeys)
                      {
                        if (writeCharacteristic != null)
                          {
                            writeCharacteristic.write(utf8.encode('/195')),
                            //f195 e176 t179 u218 d217
                          }
                      }
                    else
                      {
                        setState(() => {
                              if (_sections[currentSectionEditing].length > 2)
                                {
                                  _sections[currentSectionEditing] =
                                      _sections[currentSectionEditing] + ',',
                                },
                              _sections[currentSectionEditing] =
                                  _sections[currentSectionEditing] + 'F2',
                            })
                      },
                  }),
          RaisedButton(
              child: Text('enter'),
              onPressed: () => {
                    if (showSpecialKeys)
                      {
                        if (writeCharacteristic != null)
                          {
                            writeCharacteristic.write(utf8.encode('/176')),
                            //f195 e176 t179 u218 d217
                          }
                      }
                    else
                      {
                        setState(() => {
                              if (_sections[currentSectionEditing].length > 2)
                                {
                                  _sections[currentSectionEditing] =
                                      _sections[currentSectionEditing] + ',',
                                },
                              _sections[currentSectionEditing] =
                                  _sections[currentSectionEditing] + 'enter',
                            })
                      },
                  }),
          RaisedButton(
              child: Text('back'),
              onPressed: () => {
                    if (showSpecialKeys)
                      {
                        if (writeCharacteristic != null)
                          {
                            writeCharacteristic.write(utf8.encode('/178')),
                            //f195 e176 t179 u218 d217
                          }
                      }
                    else
                      {
                        setState(() => {
                              if (_sections[currentSectionEditing].length > 2)
                                {
                                  _sections[currentSectionEditing] =
                                      _sections[currentSectionEditing] + ',',
                                },
                              _sections[currentSectionEditing] =
                                  _sections[currentSectionEditing] + 'back',
                            })
                      },
                  }),
        ],
      ),
    );
  }

  editingOverlay() {

    if (editingSections) {
      if (_sections.length < 1 ) {
        _sections = ['First'];
      }
      editingItems = _sections
          .asMap()
          .map((index, item) => MapEntry(
              index,
              Slidable(
                actionPane: SlidableBehindActionPane(),
                actionExtentRatio: 0.20,
                key: Key(index.toString() + 'd'),
                secondaryActions: <Widget>[
                  SlideAction(
                    child: PopupMenuButton<String>(
                      offset: Offset(0, 1000),
                      onSelected: (String newValue) {
                        print(newValue);
                        if (newValue == "Text") {
                          _sections.insert(index + 1, 'Text');
                          setState(() => {

                                currentSectionEditing = index + 1,
                              });
                        } else {
                          setState(() => {
                                _sections.insert(index + 1, '**'),
                                currentSectionEditing = index + 1,
                              });
                        }
                      },
                      itemBuilder: (BuildContext context) => _popUpMenuItems,
                    ),
                  ),
                  IconSlideAction(
                    caption: 'Delete',
                    color: Colors.red,
                    icon: FlutterIcons.delete_ant,
                    onTap: () => {
                      setState(() => {
                            _sections.removeAt(index),
                          })
                    },
                  ),
                ],
                child: Container(
                  color: Colors.white,
                  child: ListTile(
                    title: editingOrNah(index, item),
                    trailing: IconButton(
                      icon: Icon(FlutterIcons.edit_ant),
                      onPressed: () => {
                        editSection(index),
                      },
                    ),
                    key: Key(index.toString()),
                  ),
                ),
              )))
          .values
          .toList();

      List<Widget> buttonBar = <Widget>[
        Expanded(
          child: FittedBox(
            child: IconButton(
              onPressed: () => {
                editingSections = false,
                _sections = oldSections,
                print(_sections + oldSections),
                updateSectionContents(),
              },
              icon: Icon(
                FlutterIcons.cancel_mco,
                color: Colors.red,
              ),
            ),
          ),
        ),
        Expanded(
          child: FittedBox(
            child: IconButton(
              onPressed: () => {
                editingSections = false,
                updateSectionContents(),
                _savePreferences(),
              },
              icon: Icon(
                FlutterIcons.check_circle_faw5,
                color: Colors.indigo,
              ),
            ),
          ),
        ),
      ];

      if (editingKeyPressSection) {
        buttonBar = <Widget>[
          Expanded(
            child: specialKeys(),
          ),
          Column(
            children: <Widget>[
              Expanded(
                child: FittedBox(
                  child: IconButton(
                    onPressed: () => {
                      print('presed'),
                      removeLastKey(),
                    },
                    icon: Icon(
                      FlutterIcons.arrow_back_mdi,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: FittedBox(
                  child: IconButton(
                    onPressed: () => {
                      setState(() => {
                            print('done editing key presses'),
                            editingKeyPressSection = false,
                            currentSectionEditing = null,
                          }),
                    },
                    icon: Icon(
                      FlutterIcons.done_mdi,
                      color: Colors.indigo,
                    ),
                  ),
                ),
              ),
            ],
          )
        ];
      }

      return Column(
        children: <Widget>[
          Expanded(
            child: Container(
              padding: EdgeInsets.all(30),
              child: Container(
                child: ReorderableListView(
                  onReorder: onReorder,
                  children: editingItems,
                  scrollController: ScrollController(),
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                ),
              ),
              decoration: BoxDecoration(color: Colors.black54),
            ),
          ),
          Container(
            padding: EdgeInsets.all(15),
            child: Container(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: buttonBar,
              ),
            ),
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
            ),
          )
        ],
      );
    }
    return Container();
  }
}

class PageTwo extends StatefulWidget {
  PageTwo({Key key, this.title}) : super(key: key);

  static const String routeName = "/PageTwo";

  final String title;

  @override
  PageTwoState createState() => PageTwoState();
}

class PageTwoState extends State<PageTwo> {
  Color progressColor = Colors.white;
  static var connectPercent = 0.0;
  Icon connectedIcon = Icon(
    MaterialCommunityIcons.lighthouse,
    size: 100,
    color: Colors.grey,
  );

  _addDeviceTolist(final BluetoothDevice device) {
    if (!devicesList.contains(device)) {
      print('adding new device');
      setState(() {
        devicesList.add(device);
      });
    }
  }

  _scan() {
    flutterBlue.connectedDevices
        .asStream()
        .listen((List<BluetoothDevice> devices) {
      for (BluetoothDevice device in devices) {
        print(device.name);
        print('connected DEVICE:::: ' + device.name.toString());
//        _addDeviceTolist(device);
      }
    });

    flutterBlue.connectedDevices
        .asStream()
        .listen((List<BluetoothDevice> devices) {
      for (BluetoothDevice device in devices) {
        print(device.name);
        print('connected DEVICE:::: ' + device.name.toString());
      }
    });

    print('starting scan...');

    flutterBlue.startScan(timeout: Duration(seconds: 4));

    flutterBlue.scanResults.listen((List<ScanResult> results) {
      for (ScanResult result in results) {
        if (result.device.id.toString().substring(0, 10) == 'B29B4DAD-A') {
//          print('found keyboard dongle');
          _addDeviceTolist(result.device);

          if (!tryingToConnect && _connectedDevice == null) {
            connectPercent = 0.5;
            tryingToConnect = true;

            _tryConnect(result.device);
          }
        }
      }
    });

    flutterBlue.stopScan();
  }

  var tryingToConnect = false;

  _tryConnect(final BluetoothDevice device) async {
    print('trying to connect');

    try {
      await device.connect();
    } catch (e) {
      print(e.toString());
      if (e.code != 'already_connected') {
        throw e;
      } else {}
    } finally {
      if (device != null) {
        connectPercent = 1;
        Future.delayed(const Duration(milliseconds: 1000), () {
          connectedIcon = Icon(
            MaterialCommunityIcons.lighthouse_on,
            size: 100,
            color: Colors.amber,
          );
          progressColor = Colors.amber;
        });
        print('nailed it finding services');
        _services = await device.discoverServices();
        _connectedDevice = device;
        tryingToConnect = false;
      }
    }
  }

  ListView _buildListViewOfDevices() {
    List<Container> containers = new List<Container>();
    for (BluetoothDevice device in devicesList) {
      containers.add(
        Container(
          height: 100,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(device.name == '' ? '(unknown device)' : device.name),
                    Text(device.id.toString()),
                  ],
                ),
              ),
              FlatButton(
                color: Colors.indigo,
                child: Text(
                  'Connect',
                  style: TextStyle(color: Colors.white),
                ),
                onPressed: () async {
                  flutterBlue.stopScan();
                  try {
                    await device.connect();
                  } catch (e) {
                    if (e.code != 'already_connected') {
                      throw e;
                    }
                  } finally {
                    _services = await device.discoverServices();
                  }
                  _connectedDevice = device;
                },
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(8),
      children: <Widget>[
        ...containers,
      ],
    );
  }

  _refresh() {
    print('refreshing');
    tryingToConnect = false;
    devicesList.clear();
    _buildListViewOfDevices();
    connectPercent = 0.0;
    progressColor = Colors.white;

    _scan();
  }

  ListView _buildView() {
    return _buildListViewOfDevices();
  }

  Container _buttonAction() {
    return Container(
      child: Padding(
          padding: EdgeInsets.all(5),
          child: Column(
              verticalDirection: VerticalDirection.up,
              children: <Widget>[
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                      color: Colors.indigoAccent.withAlpha(100),
                      borderRadius: BorderRadius.all(Radius.circular(15))),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: <Widget>[
                        Container(
                          height: 100,
                          child: FittedBox(
                            child: IconButton(

                              onPressed: _refresh,
                              icon: Icon(
                                Icons.refresh,
                              ),
                            ),
                          ),
                        ),
                      ]),
                )
              ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('TEsting'),
      ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              Flexible(
                flex: 1,
                child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Container(
                      decoration: BoxDecoration(
                        color: Colors.indigo,
                        borderRadius: BorderRadius.all(Radius.circular(15)),
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        children: <Widget>[
                          Flexible(
                            flex: 3,
                            child: FittedBox(
                                child: CircularPercentIndicator(
                              radius: 150,
                              lineWidth: 15.0,
//                              animateFromLastPercent: true,
                              animation: true,
                              animationDuration: 1000,
                              percent: connectPercent,
                              center: connectedIcon,
                              progressColor: progressColor,
                            )),
                          ),
                          Flexible(
                            flex: 1,
                            child: AutoSizeText(
                              'Connected Device',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 40),
                            ),
                          )
                        ],
                      )),
                ),
              ),
              Flexible(
                child: Column(
                  children: <Widget>[
                    Flexible(
                        child: AutoSizeText(
                      'Avaliable Devices',
                      style: TextStyle(fontSize: 20, color: Colors.indigo),
                    )),
                    Flexible(flex: 5, child: _buildView()),
                  ],
                ),
                flex: 3,
              ),
            ],
          ),
          _buttonAction()
        ],
      ),
    );
  }
}

const Duration _kExpand = const Duration(milliseconds: 200);

class AppExpansionTile extends StatefulWidget {
  const AppExpansionTile({
    Key key,
    this.leading,
    @required this.title,
    this.backgroundColor,
    this.onExpansionChanged,
    this.children: const <Widget>[],
    this.trailing,
    this.initiallyExpanded: false,
  })  : assert(initiallyExpanded != null),
        super(key: key);

  final Widget leading;
  final Widget title;
  final ValueChanged<bool> onExpansionChanged;
  final List<Widget> children;
  final Color backgroundColor;
  final Widget trailing;
  final bool initiallyExpanded;

  @override
  AppExpansionTileState createState() => new AppExpansionTileState();
}

class AppExpansionTileState extends State<AppExpansionTile>
    with SingleTickerProviderStateMixin {
  AnimationController _controller;
  CurvedAnimation _easeOutAnimation;
  CurvedAnimation _easeInAnimation;
  ColorTween _borderColor;
  ColorTween _headerColor;
  ColorTween _iconColor;
  ColorTween _backgroundColor;
  Animation<double> _iconTurns;

  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();

    _controller = new AnimationController(duration: _kExpand, vsync: this);
    _easeOutAnimation =
        new CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _easeInAnimation =
        new CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _borderColor = new ColorTween();
    _headerColor = new ColorTween();
    _iconColor = new ColorTween();
    _iconTurns =
        new Tween<double>(begin: 0.0, end: 0.5).animate(_easeInAnimation);
    _backgroundColor = new ColorTween();

    _isExpanded =
        PageStorage.of(context)?.readState(context) ?? widget.initiallyExpanded;
    if (_isExpanded) _controller.value = 1.0;

  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _activeColor = Colors.transparent;

  void setActive() {

    _activeColor = Theme.of(context).accentColor.withAlpha(100);
  }

  void setInactive() {
    _activeColor = Colors.transparent;
  }

  void expand() {
    _setExpanded(true);
  }

  void collapse() {
//    _backgroundColor = ColorTween(begin: Colors.transparent, end: Colors.transparent);
    _setExpanded(false);
  }

  void toggle() {
    _setExpanded(!_isExpanded);
  }

  void _setExpanded(bool isExpanded) {
    if (_isExpanded != isExpanded) {
      setState(() {
        _isExpanded = isExpanded;
        if (_isExpanded)
          _controller.forward();
        else
          _controller.reverse().then<void>((Null) {
            setState(() {
              // Rebuild without widget.children.
            });
          });
        PageStorage.of(context)?.writeState(context, _isExpanded);
      });
      if (widget.onExpansionChanged != null) {
        widget.onExpansionChanged(_isExpanded);
      }
    }
  }

  Widget _buildChildren(BuildContext context, Widget child) {
    final Color borderSideColor =
        _borderColor.evaluate(_easeOutAnimation) ?? Colors.transparent;
    final Color titleColor = _headerColor.evaluate(_easeInAnimation);

    return new Container(
      decoration: new BoxDecoration(
          color: _activeColor,
          // _backgroundColor.evaluate(_easeOutAnimation) ?? Colors.transparent,
          border: new Border(
            top: new BorderSide(color: borderSideColor),
            bottom: new BorderSide(color: borderSideColor),
          )),
      child: new Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconTheme.merge(
            data:
                new IconThemeData(color: _iconColor.evaluate(_easeInAnimation)),
            child: new ListTile(
              onTap: toggle,
              leading: widget.leading,
              title: new DefaultTextStyle(
                style: Theme.of(context)
                    .textTheme
                    .subhead
                    .copyWith(color: titleColor),
                child: widget.title,
              ),
              trailing: widget.trailing ??
                  new RotationTransition(
                    turns: _iconTurns,
                    child: const Icon(Icons.expand_more),
                  ),
            ),
          ),
          new ClipRect(
            child: new Align(
              heightFactor: _easeInAnimation.value,
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    _borderColor.end = theme.dividerColor;
    _headerColor
      ..begin = theme.textTheme.subhead.color
      ..end = theme.accentColor;
    _iconColor
      ..begin = theme.unselectedWidgetColor
      ..end = theme.accentColor;
    _backgroundColor.end = widget.backgroundColor;

    final bool closed = !_isExpanded && _controller.isDismissed;
    return new AnimatedBuilder(
      animation: _controller.view,
      builder: _buildChildren,
      child: closed ? null : new Column(children: widget.children),
    );
  }
}

