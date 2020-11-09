
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_icons/flutter_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'globals.dart' as globals;

class CorrectionEdit extends StatefulWidget {

  @override
  CorrectionEditState createState() => CorrectionEditState();

}

class CorrectionEditState extends State<CorrectionEdit> {
  List<List<TextEditingController>> cont = List<List<TextEditingController>>();

  int editing;

  List<List<TextEditingController>> controllers = List<List<TextEditingController>>();

  saveTable() async{
    List<List<String>> toBeSaved = List<List<String>>();
    for (List<TextEditingController> cont in controllers){
      toBeSaved.add([cont[0].text, cont[1].text]);
    }
    globals.correctionTable = toBeSaved;
    print(globals.correctionTable);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String saveString = '';
    for (List<String> row in toBeSaved) {
      saveString = saveString + '[';
      saveString = saveString + row[0] + ',' + row[1];
    }
    prefs.setString('table', saveString);
    print('saved string: ' + saveString);

    correctionTable = globals.correctionTable;
  }

  loadTable() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String loadString = prefs.getString('table');
    List<List<String>> load = List<List<String>>();
    List<String> rows = loadString.split('[');
    for (String row in rows ) {
      List<String> sets = row.split(',');
      load.add([sets[0], sets[1]]);
    }
    globals.correctionTable = load;
    correctionTable = globals.correctionTable;
    print(load);
  }

  List<List<String>> correctionTable = globals.correctionTable;

  @override
  Widget build(BuildContext context) {
    controllers = List<List<TextEditingController>>();

    List<Widget> tiles = List<Widget>();
    ListTile titles = ListTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(15)),
                color: Theme.of(context).accentColor,
              ),
              child: Text('Wrong',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white
                ),
              ),
            ),
          ),
          VerticalDivider(),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(15)),
                color: Theme.of(context).accentColor,
              ),
              child: Text('Right',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white
                ),
              ),
            ),
          ),
        ],
      ),
    );
    tiles.add(titles);
    correctionTable.asMap().forEach((key, value) {
      TextEditingController first = TextEditingController(
        text: correctionTable[key][0],
      );
      TextEditingController second = TextEditingController(
        text: correctionTable[key][1],
      );
      controllers.add([first, second]);
      ListTile tile = ListTile();
      if (key != editing) {
        tile = ListTile(
          onTap: () => setState(() => {
            editing = key
          }),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(first.text),
              VerticalDivider(),
              Text(second.text)
            ],
          ),
        );
      }else {
        tile = ListTile(
          title: Row(

            children: [
              Expanded(

                child: TextField(
                    onEditingComplete: () => setState(() => {
                      saveTable(),
                      editing = null,
                      FocusScope.of(context).unfocus()

                    }),
                    controller: first),
              ),
              VerticalDivider(),
              Expanded(
                child: TextField(
                  onEditingComplete: () => setState(() => {
                    saveTable(),
                    editing = null,
                    FocusScope.of(context).unfocus()

                  }),
                    controller: second),
              ),

            ],
          ),
        );
      }

      tiles.add(Slidable(
          actionPane: SlidableStrechActionPane(),
          secondaryActions: [
            IconSlideAction(
              caption: 'Delete',
              color: Colors.red,
              icon: FlutterIcons.delete_ant,
              onTap: () => {
                setState(() => {
                  correctionTable.removeAt(key),
                })
              },
            ),
          ],
          child: tile));
    });

    print(globals.correctionTable);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: Icon(FlutterIcons.backburger_mco,

          ),
          onPressed: () => {
            saveTable(),
            Navigator.pop(context),
          },
        ),
        title: Text('Edit Correction Table'),
      ),
      body: ListView(
        children: tiles,
      ),
      bottomNavigationBar: BottomAppBar(
        color: Theme.of(context).primaryColor,
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[ RaisedButton(onPressed: () => {
              saveTable(),
            }, child: Text('SAVE')),
              RaisedButton(onPressed: () => {
                setState(() => {
                  correctionTable.add(['wrong', 'right'])
                })
              }, child: Text('ADD'))
            ]
        ),
      ),
    );
  }

}