{ lib
, buildPythonPackage
, fetchPypi
, msrest
, msrestazure
, azure-common
, azure-mgmt-core
, pythonOlder
,
}:
buildPythonPackage rec {
  pname = "azure-mgmt-automation";
  version = "1.0.0";
  format = "setuptools";

  disabled = pythonOlder "3.6";

  src = fetchPypi {
    inherit pname version;
    extension = "zip";
    hash = "sha256-pJ0tQT/vVwEMs2Fh5bwFZgG418bQW9PLBaE1Eu8pHh4=";
  };

  propagatedBuildInputs = [
    msrest
    msrestazure
    azure-common
    azure-mgmt-core
  ];

  # has no tests
  doCheck = false;

  pythonImportsCheck = [
    "azure.mgmt.automation"
  ];

  meta = with lib; {
    description = "This is the Microsoft Azure Automation Services Client Library";
    homepage = "https://github.com/Azure/azure-sdk-for-python";
    license = licenses.mit;
    maintainers = with maintainers; [ maxwilson ];
  };
}
