part of '../main.dart';
Map<String,Object?> _encodeDraft(Object value) {
  if(value is SerialDraft)return {'imei':value.imei,'color':value.color,'conditionText':value.conditionText,'cost':value.cost};
  if(value is PurchaseLineDraft)return {'product':value.product,'quantity':value.quantity,'cost':value.cost.text,'discount':value.discount.text,'serials':value.serials.map(_encodeDraft).toList()};
  if(value is SaleLineDraft)return {'product':value.product,'quantity':value.quantity,'unitPrice':value.unitPrice,'discountPerItem':value.discountPerItem,'serialId':value.serialId,'imei':value.imei,'color':value.color};
  throw ArgumentError('Loại dòng hàng không hợp lệ');
}
SerialDraft _decodeSerialDraft(Map<String,Object?> v)=>SerialDraft(imei:v['imei'] as String,color:v['color'] as String? ?? '',conditionText:v['conditionText'] as String? ?? 'Mới',cost:v['cost'] as int? ?? 0);
PurchaseLineDraft _decodePurchaseLineDraft(Map<String,Object?> v){
 final draft=PurchaseLineDraft(product:Map<String,Object?>.from(v['product'] as Map),initialQuantity:v['quantity'] as int);
 draft.cost.text=v['cost'] as String;draft.discount.text=v['discount'] as String;
 draft.serials..clear()..addAll((v['serials'] as List).map((r)=>_decodeSerialDraft(Map<String,Object?>.from(r as Map))));
 return draft;
}
SaleLineDraft _decodeSaleLineDraft(Map<String,Object?> v)=>SaleLineDraft(product:Map<String,Object?>.from(v['product'] as Map),quantity:v['quantity'] as int,unitPrice:v['unitPrice'] as int,discountPerItem:v['discountPerItem'] as int,serialId:v['serialId'] as int?,imei:v['imei'] as String? ?? '',color:v['color'] as String? ?? '');
