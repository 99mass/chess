import 'package:chess/constant/constants.dart';
import 'package:flutter/material.dart';

class CustomAlertDialog extends StatelessWidget {
  final VoidCallback? onOk;
  final String? titleMessage;
  final String? subtitleMessage;
  final int typeDialog;
  final VoidCallback? onAccept;
  final VoidCallback? onCancel;
  final String? logo;

  const CustomAlertDialog({
    super.key,
    this.titleMessage,
    this.subtitleMessage,
    this.typeDialog = 0,
    this.onOk,
    this.onAccept,
    this.onCancel,
    this.logo,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: contentBox(context),
    );
  }

  Widget contentBox(context) {
    return Stack(
      children: <Widget>[
        Container(
          padding:
              const EdgeInsets.only(left: 20, top: 65, right: 20, bottom: 20),
          margin: const EdgeInsets.only(top: 45),
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            color: ColorsConstants.colorBg,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black, offset: Offset(0, 10), blurRadius: 10),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                titleMessage ?? "",
                style: const TextStyle(
                    fontSize: 22,
                    color: ColorsConstants.white,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 15),
              Text(
                subtitleMessage ?? "",
                style:
                    const TextStyle(fontSize: 14, color: ColorsConstants.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  if (typeDialog == 0)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(false);
                        if (onOk != null) {
                          onOk!();
                        }
                      },
                      child: const Text(
                        "Fermer",
                        style: TextStyle(
                            fontSize: 18, color: ColorsConstants.colorGreen),
                      ),
                    ),
                  //
                  if (typeDialog == 1)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(false);
                      },
                      child: const Text(
                        "Continuer",
                        style: TextStyle(
                            fontSize: 18, color: ColorsConstants.colorGreen),
                      ),
                    ),
                  //
                  if (typeDialog == 1)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(true);
                      },
                      child: const Text(
                        "Quitter",
                        style: TextStyle(
                            fontSize: 18, color: ColorsConstants.colorBg3),
                      ),
                    ),
                  if (typeDialog == 2)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(false);
                        if (onAccept != null) {
                          onAccept!();
                        }
                      },
                      child: const Text(
                        "Accepter",
                        style: TextStyle(
                            fontSize: 18, color: ColorsConstants.colorGreen),
                      ),
                    ),
                  //
                  if (typeDialog == 2)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(false);
                        if (onCancel != null) {
                          onCancel!();
                        }
                      },
                      child: const Text(
                        "Refuser",
                        style: TextStyle(
                            fontSize: 18, color: ColorsConstants.colorBg3),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          child: CircleAvatar(
            backgroundColor: ColorsConstants.colorBg2,
            radius: 45,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(45)),
              child: Image.asset(
                logo ?? "assets/chess_logo.png",
                width: 50,
                height: 50,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
