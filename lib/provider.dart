import 'package:Openbook/pages/auth/create_account/blocs/create_account.dart';
import 'package:Openbook/services/localization.dart';
import 'package:Openbook/services/validation.dart';
import 'package:flutter/material.dart';

class OpenbookProvider extends InheritedWidget {
  CreateAccountBloc createAccountBloc = CreateAccountBloc();
  ValidationService validationService = ValidationService();
  LocalizationService localizationService;

  OpenbookProvider(child) : super(child: child) {
    createAccountBloc.setValidationService(validationService);
  }

  @override
  bool updateShouldNotify(InheritedWidget oldWidget) {
    return true;
  }

  setLocalizationService(LocalizationService newLocalizationService) {
    localizationService = newLocalizationService;
    createAccountBloc.setLocalizationService(localizationService);
  }

  setValidationService(ValidationService newValidationService) {
    validationService = newValidationService;
    createAccountBloc.setValidationService(validationService);
  }

  static OpenbookProvider of(BuildContext context) {
    return context.inheritFromWidgetOfExactType(OpenbookProvider);
  }
}