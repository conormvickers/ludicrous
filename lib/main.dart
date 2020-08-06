import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BLE Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: MyHomePage(title: 'Flutter BLE Demo'),
      );
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;
  final FlutterBlue flutterBlue = FlutterBlue.instance;
  final List<BluetoothDevice> devicesList = new List<BluetoothDevice>();
  final Map<Guid, List<int>> readValues = new Map<Guid, List<int>>();

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _writeController = TextEditingController();
  BluetoothDevice _connectedDevice;
  List<BluetoothService> _services;

  _addDeviceTolist(final BluetoothDevice device) {
    if (!widget.devicesList.contains(device)) {
      print('adding new device');
      setState(() {
        widget.devicesList.add(device);
      });
    }
  }

  @override
  void initState()  {
    super.initState();
    _scan();
  }

  _refresh () {
    setState(() {
      widget.devicesList.clear();
      _buildListViewOfDevices();
    });

//    sleep(Duration(seconds: 1));
    _scan();
  }

  Color IndicatorColor = Colors.blue;
  _scan () {

//    widget.flutterBlue.connectedDevices
//        .asStream()
//        .listen((List<BluetoothDevice> devices) {
//      for (BluetoothDevice device in devices) {
//        print(device.name);
//        print('connected');
//        _addDeviceTolist(device);
//      }
//    });

    widget.flutterBlue.startScan(timeout: Duration(seconds: 4));

    print('starting scan...');
    setState(() {
      IndicatorColor = Colors.red;
    });

    widget.flutterBlue.scanResults.listen((List<ScanResult> results) {
      for (ScanResult result in results) {

        if (result.device.id.toString().substring(0,10) == 'B29B4DAD-A') {
          print('found keyboard dongle');
          _addDeviceTolist(result.device);
          setState(() {
            IndicatorColor = Colors.orange;
          });


          if (!tryingToConnect && _connectedDevice == null) {

            Future.delayed(const Duration(milliseconds: 500), () {
              print('delay over');
              IndicatorColor = Colors.deepOrange;
              _tryConnect(result.device);
            });
          }

        }
      }
    });

    widget.flutterBlue.stopScan();

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
      }else{

      }
    } finally {
      print('nailed it finding services');
      _services = await device.discoverServices();
    }

    setState(() {
      IndicatorColor = Colors.green;
      _connectedDevice = device;
      tryingToConnect = false;
    });
  }

  BluetoothDevice deviceKeyboard;
  ListView _buildListViewOfDevices() {
    List<Container> containers = new List<Container>();
    for (BluetoothDevice device in widget.devicesList) {
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
                color: Colors.blue,
                child: Text(
                  'Connect',
                  style: TextStyle(color: Colors.white),
                ),
                onPressed: () async {
                  widget.flutterBlue.stopScan();
                  try {
                    await device.connect();
                  } catch (e) {
                    if (e.code != 'already_connected') {
                      throw e;
                    }
                  } finally {
                    _services = await device.discoverServices();
                  }
                  setState(() {
                    _connectedDevice = device;
                  });
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

  List<ButtonTheme> _buildReadWriteNotifyButton(
      BluetoothCharacteristic characteristic) {
    List<ButtonTheme> buttons = new List<ButtonTheme>();

    if (characteristic.properties.read) {
      buttons.add(
        ButtonTheme(
          minWidth: 10,
          height: 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: RaisedButton(
              color: Colors.blue,
              child: Text('READ', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                var sub = characteristic.value.listen((value) {
                  setState(() {
                    widget.readValues[characteristic.uuid] = value;
                  });
                });
                await characteristic.read();
                sub.cancel();
              },
            ),
          ),
        ),
      );
    }
    if (characteristic.properties.write) {
      buttons.add(
        ButtonTheme(
          minWidth: 10,
          height: 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: RaisedButton(
              child: Text('WRITE', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: Text("Write"),
                        content: Row(
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: _writeController,
                              ),
                            ),
                          ],
                        ),
                        actions: <Widget>[
                          FlatButton(
                            child: Text("Send"),
                            onPressed: () {
                              characteristic.write(
                                  utf8.encode(_writeController.value.text));
                              Navigator.pop(context);
                            },
                          ),
                          FlatButton(
                            child: Text("Cancel"),
                            onPressed: () {
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      );
                    });
              },
            ),
          ),
        ),
      );
    }
    if (characteristic.properties.notify) {
      buttons.add(
        ButtonTheme(
          minWidth: 10,
          height: 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: RaisedButton(
              child: Text('NOTIFY', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                characteristic.value.listen((value) {
                  widget.readValues[characteristic.uuid] = value;
                });
                await characteristic.setNotifyValue(true);
              },
            ),
          ),
        ),
      );
    }

    return buttons;
  }

  BluetoothCharacteristic writeCharacteristic;

  List<String> _sections = ['new', 'complaint'];

  List<TextEditingController> _controllers = List<TextEditingController>();

  ListView _buildConnectDeviceView() {
    List<Container> containers = new List<Container>();
    if (_controllers != null) {
      _controllers.clear();
    }


    for (BluetoothService service in _services) {


      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.uuid.toString().substring(0, 1) == '6') {
          writeCharacteristic = characteristic;
        }
      }

    }

    for (String section in _sections){
      List<Widget> characteristicsWidget = new List<Widget>();
      TextEditingController addControler = new TextEditingController();
      _controllers.add(addControler);
      characteristicsWidget.add(
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: addControler,
                    ),
                  ),
                  Container(

                    height: 50,
                    child: FittedBox(
                      fit: BoxFit.fitWidth,
                      child: FloatingActionButton(

                        onPressed: _sendBox,
                        child: Icon(Icons.add_to_home_screen,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              Divider(),
            ],
          ),
        ),
      );

      containers.add(
        Container(
          child: ExpansionTile(
              title: Text(section),
              children: <Widget>[
                ...characteristicsWidget,
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



  ListView _buildView() {
    if (_connectedDevice != null) {
      return _buildConnectDeviceView();
    }
    return _buildListViewOfDevices();
  }

  _sendTesting () async {
    if (writeCharacteristic != null) {
      print('sending some data over');
      writeCharacteristic.write(utf8.encode('vickerc1/t'));
      writeCharacteristic.write(utf8.encode('1qaz@WSX1qaz@WSX/n'));
    }
  }

  _epicLogin () async {
    if (writeCharacteristic != null) {
      print('sending some data over');
      writeCharacteristic.write(utf8.encode('vickerc1/t'));
      writeCharacteristic.write(utf8.encode('1qaz@WSX1qaz@WSX/n'));
      writeCharacteristic.write(utf8.encode('/n/n'));
    }
  }

  _searchAgain() async{
    print('disconnecting');
    IndicatorColor = Colors.blue;

    _connectedDevice.disconnect();
    _connectedDevice = null;
    widget.devicesList.clear();
    setState(() {
//      _refresh();
    });
  }

  Padding _buttonAction() {
    if (_connectedDevice == null) {
      return Padding(
        padding: EdgeInsets.all(15),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(

                height: 100,
                child: FittedBox(
                  child: FloatingActionButton(

                    backgroundColor: IndicatorColor,
                    onPressed: _refresh,
                    child: Icon(Icons.refresh,
                    ),
                  ),
                ),
              )
            ]

        ),
      );
    }
    return Padding(
      padding: EdgeInsets.all(15),

      child: Column(
        verticalDirection: VerticalDirection.up,
        children: <Widget>[

          Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,

              children: <Widget>[
                Container(
                  height: 100,
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    child: FloatingActionButton(
                      onPressed: _searchAgain,
                      child: Icon(Icons.undo,
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 100,
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    child: FloatingActionButton(

                      onPressed: _sendTesting,
                      child: Icon(Icons.send,
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 100,
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    child: FloatingActionButton(

                      onPressed: _epicLogin,
                      child: Icon(Icons.exit_to_app,
                      ),
                    ),
                  ),
                ),
              ]
          ),

        ],
      ),
    );

  }
  static final myController = TextEditingController();
  var toSendTest = (
   TextFormField(
     controller: myController,
      decoration: InputDecoration(
      labelText: 'to send'
      ),
   ));


  _sendBox() async {
    print('send pressed');
      if (writeCharacteristic != null) {
        print('sending some data over');
//        var data = myController.value.text.toString();
        String data = "";
        for (TextEditingController cont in _controllers) {
          print(cont.value.text.toString());
          data = data + cont.value.text.toString();
        }


        print(data);
        List<String> stack = List<String>();
        print((data.length / 20).floor());
        if (data.length > 20) {
          for (var i = 0; i < ((data.length / 20).floor() + 1); i++) {
            print(i);
            if (i != (data.length / 20).floor()  ) {
              print(data.substring(20 * i , 20 * i + 19).toString());
              stack[i] = (data.substring(20 * i, 20 * i + 20).toString());
              print(stack);

            }else{
              print(data.substring(20 * i ).toString());
              stack[i] = (data.substring(20 * i));

              print(stack);
            }
          }
        }
        print(stack);
        if (stack.length > 0) {
          print('long stack');
          for (var i = 0; i < stack.length; i++) {
            writeCharacteristic.write(utf8.encode(stack[i]));
          }
        } else {
          print('short stack');
          writeCharacteristic.write(utf8.encode(data));
        }
      }
      else{
        print('couldnt find characteristic');
      }

  }
  _newChunk () {

  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: _buildView(),

        floatingActionButton: _buttonAction()

      );
}
