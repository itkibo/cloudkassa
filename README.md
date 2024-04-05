<p align="right">
  <img src="https://img.shields.io/badge/language-powershell-skyblue?style"/>
</p>
# Cloud kassa backend engine
> A solution for mass posting of receipts to cash registers  
> It's useful if you do not want to buy and set up physical cash registers  
> Generate receipts in json based on uploads from client banks and send them to cloud cashiers  
> Nothing will be lost thanks to logging of all actions and humanreadable reports in excel

- [x] parses upload files from client banks: gpb, sbp
- [x] extracts data and generates receipts in json
- [x] sends receipts to the Ferma API service OFD.RU
- [x] generates reports on submitted documents
- [x] detailed logging of all operations
- [x] archives sent packages and log files
- [x] works in production and sandbox modes depends on config file

config example
---
```ini
[parser]
; exclude organisations list for parser
pathExcludeOrgList = ".\exclude.txt"
; basic receipt template
pathReceiptTemplate = ".\receipt.json"
[tree]
; main package processing queue folder
dirQueue = ".\queue"
; compressed packages folder
dirZip = ".\zip"
; input - source user's txt files
dirSource = "..\_source"
; output - result reports for users
dirReport = "..\_report"
[auth]
; ferma api auth
uri = "https://ferma-test.ofd.ru/api/Authorization/CreateAuthToken"
login = "login"
password = "password"
; actual token updated from server
pathAuthTokenJson = ".\token.json"
[push]
; ferma api push
uri = "https://ferma-test.ofd.ru/api/kkt/cloud/receipt"
```
log example
---
```
2020-11-27-170911	current config file: debug.ini
2020-11-27-170911	script D E B U G mode enabled
2020-11-27-170911	will be used ferma-test api
2020-11-27-170911	------------------------------
2020-11-27-170911	auth token: f4ea525c-5d3e-4b77-8b64-168ad9cb2dbe
2020-11-27-170911	new package name: 20201127-170911-34
{
    "mode":  "debug",
    "source":  ".\\queue\\20201127-170911-34\\source",
    "package":  ".\\queue\\20201127-170911-34",
    "report":  "..\\_report\\20201127-170911-34",
    "zip":  ".\\zip",
    "filescount":  1,
    "name":  "20201127-170911-34",
    "files":  [
                  "D:\\app\\_code\\ps\\CloudKassa\\_source\\sber\\ОСБ0_1receipt_HUMAN.txt"
              ],
    "result":  ".\\queue\\20201127-170911-34\\result"
}
2020-11-27-170911	package 20201127-170911-34 processing...
2020-11-27-170911	 > source file: ОСБ0_1receipt_HUMAN.txt
2020-11-27-170911	 > file type: BankStatementSber
2020-11-27-170912	 > docs counter human/other/total: 1/1/2
2020-11-27-170912	 > receipts count: 1 preparing...
2020-11-27-170912	 > receipts count: 1 prepared
2020-11-27-170912	pushing all receipts...
2020-11-27-170912	 > file: ОСБ0_1receipt_HUMAN.txt
2020-11-27-170912	 > pushing count: 1 receipts...
2020-11-27-170912	 > receipts pushed success/error/total: 1/0/1
2020-11-27-170912	 > sum success/error/total: 2612/0/2612
2020-11-27-170912	 > duration: 0:00:00,1625701
2020-11-27-170912	 > !SUCCESS
2020-11-27-170912	^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
2020-11-27-170912	total statistics for package: 20201127-170911-34
2020-11-27-170912	receipts pushed success/error/total: 1/0/1
2020-11-27-170912	sum pushed success/error/total: 2612/0/2612
2020-11-27-170912	duration: 0:00:00,1625701
2020-11-27-170912	!SUCCESS TOTAL :)
2020-11-27-170912	^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
2020-11-27-170912	compressing package...
2020-11-27-170912	package moved from the queue folder
2020-11-27-170913	package zipped 2.7939453125 Kbite .\zip\20201127-170911-34.zip
2020-11-27-170913	calculate and saving reports...
2020-11-27-170913	done
2020-11-27-170913	-
```
report example .csv
---
```
Дата время;Порядковый №;Сумма;Чек отправлен (1-да, 0-нет);ID чека внутренний;ID чека внешний (ferma OFD)
27.11.2020 17:09:12;000001;2612;1;20201127-170911-34@20201127-170912-11@000001;0f2bc370-01f3-4af1-a03b-52d45b7701b7

Файл;Отправлено чеков;Не отправлено чеков;Всего чеков;Отправлено сумма;Не отправлено сумма;Всего сумма
ОСБ0_1receipt_HUMAN.txt;1;0;1;2612;0;2612

#@debug mode@#
```


