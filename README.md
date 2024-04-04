# Cloud kassa backend engine
> A solution for mass posting of receipts to cash registers.  
> It's useful if you do not want to buy and set up physical cash registers.  
> Generate receipts in json based on uploads from client banks and send them to cloud cashiers.  
> Nothing will be lost thanks to logging of all actions and humanreadable reports in excel.

+ parses upload files from client banks: gpb, sbp
+ extracts data and generates receipts in json
+ sends receipts to the Ferma API service OFD.RU
+ generates reports on submitted documents
+ detailed logging of all operations
+ archives sent packages and log files
