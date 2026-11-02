import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/local_network_permission_pigeon.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/app/src/main/kotlin/app/sushi/api/LocalNetworkPermissionPigeon.g.kt',
    kotlinOptions: KotlinOptions(
      includeErrorClass: false,
    ),
    dartPackageName: 'nl_jknaapen_fladder.settings',
  ),
)
@HostApi()
abstract class LocalNetworkPermissionPigeon {
  int getAndroidSdkInt();
}
