# أوامر Rectangle في Terminal لتفضيلات مخفية

نافذة التفضيلات مُصمّمة بشكل ضيّق عمدًا، لكن هناك الكثير من التعديلات التي يمكن إجراؤها عبر Terminal. بعد تنفيذ أمر Terminal، قم بإعادة تشغيل التطبيق حيث تُحمل هذه القيم عند بدء تشغيل التطبيق. بالنسبة لـ Rectangle Pro، يُرجى استبدال `com.knollsoft.Rectangle` بـ `com.knollsoft.Hookshot` في الأوامر التالية.

## المحتويات

- [أوامر Rectangle في Terminal لتفضيلات مخفية](#أوامر-rectangle-في-terminal-لتفضيلات-مخفية)
  - [المحتويات](#المحتويات)
  - [اختصارات لوحة المفاتيح](#اختصارات-لوحة-المفاتيح)
  - [ضبط السلوك على الأوامر المكررة](#ضبط-السلوك-على-الأوامر-المكررة)
  - [التبديل بين الثُلثين في حالة تكرار أوامر التوسيط النصفي](#التبديل-بين-الثُلثين-في-حالة-تكرار-أوامر-التوسيط-النصفي)
  - [تغيير الحجم عند التحرك باتجاه](#تغيير-الحجم-عند-التحرك-باتجاه)
  - [ضبط حجم macOS Ventura Stage Manager](#ضبط-حجم-macos-ventura-stage-manager)
  - [تمكين وضع المهام (Todo Mode)](#تمكين-وضع-المهام-todo-mode)
  - [السماح بالسحب للتثبيت عند ضغط مفاتيح الموديفاير](#السماح-بالسحب-للتثبيت-عند-ضغط-مفاتيح-الموديفاير)
  - [التكبير الشبه كامل (Almost Maximize)](#التكبير-الشبه-كامل-almost-maximize)
  - [إضافة أمر توسيط إضافي بحجم مخصص](#إضافة-أمر-توسيط-إضافي-بحجم-مخصص)
  - [إضافة أوامر تحجيم إضافية للتسعثات](#إضافة-أوامر-تحجيم-إضافية-للتسعثات)
  - [إضافة أوامر تحجيم إضافية للثمانيات](#إضافة-أوامر-تحجيم-إضافية-للثمانيات)
  - [إضافة أوامر تحجيم إضافية للثُلثيات](#إضافة-أوامر-تحجيم-إضافية-للثُلثيات)
  - [تعديل "مظهر البصمة" المعروضة للسحب لمنطقة الرصف](#تعديل-مظهر-البصمة-المعروضة-للسحب-لمنطقة-الرصف)
  - [التحرك لأعلى / لأسفل / لليسار / لليمين: عدم التركيز على الحافة](#التحرك-لأعلى--لأسفل--لليسار--لليمين-عدم-التركيز-على-الحافة)
  - [تحديد حدود الحجم الأدنى](#تحديد-حدود-الحجم-الأدنى)
  - [حجم الزيادة / الانقاص للتكبير والتصغير](#حجم-الزيادة--الانقاص-للتكبير-والتصغير)
  - [تصغير / تكبير النوافذ مع حواش فارغة](#تصغير--تكبير-النوافذ-مع-حواش-فارغة)
  - [تعطيل استعادة النافذة عند نقلها](#تعطيل-استعادة-النافذة-عند-نقلها)
  - [تغيير الهوامش لمناطق الرصف](#تغيير-الهوامش-لمناطق-الرصف)
  - [تعيين حواش عند حواف الشاشة](#تعيين-حواش-عند-حواف-الشاشة)
  - [تجاهل مناطق السحب المحددة للرصف](#تجاهل-مناطق-السحب-المحددة-للرصف)
  - [تعطيل الحواش عند التكبير](#تعطيل-الحواش-عند-التكبير)
  - [تمكين مناطق الرصف للأسدس](#تمكين-مناطق-الرصف-للأسدس)
  - [نقل المؤشر مع النافذة](#نقل-المؤشر-مع-النافذة)
  - [منع النافذة التي يتم سحبها بسرعة فوق شريط القوائم من الانتقال إلى مركز التح](#منع-النافذة-التي-يتم-سحبها-بسرعة-فوق-شريط-القوائم-من-الانتقال-إلى-مركز-التح)
  - [تغيير سلوك النقر المزدوج على شريط عنوان النافذة](#تغيير-سلوك-النقر-المزدوج-على-شريط-عنوان-النافذة)

 بسرعة فوق شريط القائمة من الانتقال إلى Mission Control](#منع-النافذة-التي-تم-سحبها-بسرعة-فوق-شريط-القائمة-من-الانتقال-إلى-mission-control)
- [تغيير سلوك النقر المزدوج على شريط عنوان النافذة](#تغيير-سلوك-النقر-المزدوج-على-شريط-عنوان-النافذة)

## اختصارات لوحة المفاتيح

إذا كنت ترغب في تغيير الاختصارات الافتراضية بعد أول تشغيل، انقر على "استعادة الاختصارات الافتراضية" في علامة التبويب إعدادات نافذة التفضيلات. بدلاً من ذلك، يمكنك ضبطها باستخدام الأمر التالي في Terminal ثم قم بإعادة تشغيل التطبيق. القيمة True تعني استخدام الاختصارات الموصى بها، بينما القيمة False تعني استخدام اختصارات Spectacle.

```bash
defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true
```

## ضبط السلوك على الأوامر المكررة

هذا السلوك متوفر الآن في نافذة التفضيلات، ولكن هناك خيار في التفضيلات يُسمى "التحرك إلى العرض المجاور عند تكرار أوامر اليسار أو اليمين". إذا لم يتم التحقق من هذا الإعداد، فسيتم تكرار عرض النافذة عبر الأحجام التالية عند تنفيذ إجراء النصف أو الربع: 1/2 -> 2/3 -> 1/3.

يمكن تعطيل سلوك التكرار بالكامل باستخدام الأمر التالي:

```bash
defaults write com.knollsoft.Rectangle subsequentExecutionMode -int 2
```

`subsequentExecutionMode` يقبل القيم التالية:
0: الانقسام إلى ثلاثة أجزاء حسب سلوك Spectacle (علامة غير محددة)
1: التبديل بين العروض (علامة محددة) للإجراءات اليسرى/اليمنى
2: تم الإلغاء
3: التبديل بين العروض للإجراءات اليسرى/اليمنى، والانقسام إلى ثلاثة أجزاء للباقي (سلوك Rectangle القديم)
4: تكرار نفس الإجراء على العرض التالي

## التبديل بين الثُلثين في حالة تكرار أوامر التوسيط النصفي

تحديد الحجم الذي تبدأ به عند تكرار أوامر التوسيط النصفي وتغييره بمقدار الثُلث. 1/2 -> 2/3 -> 1/3.

```bash
defaults write com.knollsoft.Rectangle centerHalfCycles -int 1
```

## تغيير الحجم عند التحرك باتجاه

بشكل افتراضي، لن يتم تغيير حجم النافذة عند استخدام الأوامر للتحرك إلى بعض الحواف. إذا تم تفعيل `resizeOnDirectionalMove`، ستُستخدم بدلاً من ذلك طريقة "النصفين إلى الثُلثين". هذا يعني أنه عند التحرك لليسار أو اليمين، سيتم تغيير العرض، وعند التحرك للأعلى أو الأسفل، سيتم تغيير الارتفاع. سيتم تكرار هذا الحجم بين 1/2 -> 2/3 -> 1/3 من عرض/ارتفاع الشاشة.

يرجى ملاحظة أنه إذا تم ضبط وضع التنفيذ التالي على التبديل بين العروض عند تفعيل هذا الخيار، فإن تحريك لليسار واليمين سيؤدي دائمًا إلى تغيير الحجم إلى 1/2، والضغط عليه مرة أخرى سينتقل إلى العرض التالي.

```bash
defaults write com.knollsoft.Rectangle resizeOnDirectionalMove -bool true
```

## ضبط حجم macOS Ventura Stage Manager

بشكل افتراضي، سيتم ضبط منطقة Stage Manager على 190 إذا تم تفعيلها.

```bash
defaults write com.knollsoft.Rectangle stageSize -float <VALUE>
```

لتحديد نسبة من عرض شاشتك، ضع قيمة بين 0 و 1.

```bash
defaults write com.k

nollsoft.Rectangle stageSize -float <VALUE_BETWEEN_0_AND_1>
```

## تمكين وضع المهام (Todo Mode)

انظر إلى [الويكي](https://github.com/rxhanson/Rectangle/wiki/Todo-Mode) لمزيد من المعلومات.

```bash
defaults write com.knollsoft.Rectangle todo -int 1
```

## السماح بالسحب للتثبيت عند ضغط مفاتيح الموديفاير

يمكن دمج قيم مفاتيح الموديفاير باستخدام العملية الجمعية (OR).

| مفتاح الموديفاير | القيمة الصحيحة |
|-----------------|---------------|
| cmd             | 1048576       |
| option          | 524288        |
| ctrl            | 262144        |
| shift           | 131072        |
| fn              | 8388608       |

مثال على الأمر لتقييد التثبيت بالمفتاح cmd:

```bash
defaults write com.knollsoft.Rectangle snapModifiers -int 1048576
```

## التكبير الشبه كامل (Almost Maximize)

بشكل افتراضي، ستُعيد "التكبير الشبه كامل" حجم النافذة إلى 90% من الشاشة (العرض والارتفاع).

```bash
defaults write com.knollsoft.Rectangle almostMaximizeHeight -float <VALUE_BETWEEN_0_&_1>
```

```bash
defaults write com.knollsoft.Rectangle almostMaximizeWidth -float <VALUE_BETWEEN_0_&_1>
```

## إضافة أمر توسيط إضافي بحجم مخصص

هذا الأمر الإضافي غير متوفر في واجهة المستخدم. ستحتاج إلى معرفة رمز المفتاح وعلامات الموديفاير التي ترغب في استخدامها (يمكنك استخدام تطبيق مفاتيح مجاني للحصول على رموز المفاتيح: <https://apps.apple.com/us/app/key-codes/id414568915>)

```bash
defaults write com.knollsoft.Rectangle specified -dict-add keyCode -float 8 modifierFlags -float 1966080
```

```bash
defaults write com.knollsoft.Rectangle specifiedHeight -float 1050
defaults write com.knollsoft.Rectangle specifiedWidth -float 1680
```

## إضافة أوامر تحجيم إضافية للتسعثات

الأوامر الخاصة بتحجيم النافذة إلى التسعثات غير متوفرة في واجهة المستخدم. على غرار التوسيط الإضافي، ستحتاج إلى معرفة رمز المفتاح وعلامات الموديفاير التي ترغب في استخدامها.

أكواد المفاتيح هي:

* topLeftNinth
* topCenterNinth
* topRightNinth
* middleLeftNinth
* middleCenterNinth
* middleRightNinth
* bottomLeftNinth
* bottomCenterNinth
* bottomRightNinth

على سبيل المثال، يُمكن تعيين أمر الاختصار للتسعث العلوي الأيسر إلى `ctrl opt shift 1` باستخدام الأمر التالي:

```bash
defaults write com.knollsoft.Rectangle topLeftNinth -dict-add keyCode -float 18 modifierFlags -float 917504
```

## إضافة أوامر تحجيم إضافية للثمانيات

الأوامر الخاصة بتحجيم النافذة إلى الثمانيات غير متوفرة في واجهة المستخدم. هذا يقسم الشاشة إلى شبكة 4x2.

أكواد المفاتيح هي:

* topLeftEighth
* topCenterLeftEighth
* topCenterRightEighth
* topRightEighth
* bottomLeftEighth
* bottomCenterLeftEighth
* bottomCenterRightEighth
* bottomRightEighth

على سبيل المثال، يُمكن تعيين أمر الاختصار للثماني العلوي الأيسر إلى `ctrl opt shift 1` باستخدام الأمر التالي:

```bash
defaults write com.knollsoft.Rectangle topLeftEighth -dict-add keyCode -float 18 modifierFlags -float 917504
```

## إضافة أوامر تحجيم إضافية للثُلثيات

هذه الأوامر الخاصة بتحجيم النافذة إلى الركن الثُلث غير متوفرة في واجهة المستخدم ولكن يمكن تكوينها عبر سطر الأوامر.

أكواد المفاتيح هي:

* topLeftThird
* topRightThird
* bottomLeftThird
* bottomRightThird

(تتوافق هذه الأكواد مع الثُلث، وعند تكرارها ستتنقل في كل من الحسابات)

على سبيل المثال، يُمكن تعيين أمر الاختصار للثُلث العلوي الأيسر إلى `ctrl opt shift 1` باستخدام الأمر التالي:

```bash
defaults write com.knollsoft.Rectangle topLeftThird -dict-add keyCode -float 18 modifierFlags -float 917504
```

تحسن، سأقوم بترجمة المحتوى إلى العربية وترتيب النص العربي من اليمين إلى اليسار. يُرجى التأكد من أن الشفرة العربية ستظهر بشكل صحيح عندما يتم تطبيقها في نص محرر يدعم النص العربي، مثل محرر النصوص في نظام التشغيل macOS.

```
## إضافة أوامر للتجانب والتكدس الإضافية

الأوامر المستخدمة للتجانب والتكدس للنوافذ المرئية غير متوفرة في واجهة المستخدم ولكن يمكن تكوينها عبر سطر الأوامر.

أكواد المفاتيح هي:

* tileAll
* cascadeAll
* cascadeActiveApp

_tileAll_ و _cascadeAll_ يتم تطبيقهما على جميع النوافذ المرئية.

تكدس التطبيق النشط فقط وجلب النوافذ الخاصة به إلى الأمام، متركاً جميع النوافذ الأخرى دون تغيير.

على سبيل المثال، الأمر لتعيين اختصار cascadeActiveApp إلى `ctrl shift 2` سيكون:

```bash
defaults write com.knollsoft.Rectangle cascadeActiveApp -dict-add keyCode -float 2 modifierFlags -float 393475
```

## تعديل "مظهر البصمة" المعروضة للسحب لمنطقة الرصف

ضبط الشفافية (الألفا). القيمة الافتراضية هي 0.3.

```bash
defaults write com.knollsoft.Rectangle footprintAlpha -float <قيمة_بين_0_و_1>
```

تغيير عرض الحدود. القيمة الافتراضية هي 2 (كانت 1 في السابق).

```bash
defaults write com.knollsoft.Rectangle footprintBorderWidth -float <عدد_البكسل>
```

تعطيل التلاشي.

```bash
defaults write com.knollsoft.Rectangle footprintFade -int 2
```

تغيير اللون.

```bash
defaults write com.knollsoft.Rectangle footprintColor -string "{\"red\":0,\"blue\":0.5,\"green\":0.5}"
```

تغيير مدة الرسوم المتحركة. القيمة هي مضاعف. القيمة الافتراضية هي 0 (لا توجد رسوم متحركة).

```bash
defaults write com.knollsoft.Rectangle footprintAnimationDurationMultiplier -float <مضاعف>
```

## التحرك لأعلى / لأسفل / لليسار / لليمين: عدم التركيز على الحافة

بشكل افتراضي، التحرك الاتجاهي سيجعل النافذة في وسط الحافة التي يتم نقلها إليها.

```bash
defaults write com.knollsoft.Rectangle centeredDirectionalMove -int 2
```

## تحديد حدود الحجم الأدنى

بشكل افتراضي، سيقلل "Make Smaller" النافذة حتى تصل إلى 25% من الشاشة (العرض والارتفاع).

```bash
defaults write com.knollsoft.Rectangle minimumWindowWidth -float <قيمة_بين_0_و_1>
```

```bash
defaults write com.knollsoft.Rectangle minimumWindowHeight -float <قيمة_بين_0_و_1>
```

## حجم الزيادة / الانقاص للتكبير والتصغير

بشكل افتراضي، "Make Smaller" و "Make Larger" ستغير حجم ارتفاع / عرض النافذة بمقدار 30 بكسل.

```bash
defaults write com.knollsoft.Rectangle sizeOffset -float <عدد_البكسل>
```

## تصغير / تكبير النوافذ مع حواش فارغة

بشكل افتراضي، النوافذ الملامسة لحافة الشاشة ستحتفظ بتلك الحواف المشتركة بينما سيتم تغيير حجم الحافة غير المشتركة فقط. مع الحواش الفارغة، هذا يجعل الأمر مبهمًا قليلاً حيث لا تلامس الحواف بالفعل الشاشة، لذا يمكنك تعطيله للتغيير التقليدي والمرن:

```bash
defaults write com.knollsoft.Rectangle curtainChangeSize -int 2
```

## تعطيل استعادة النافذة عند نقلها

```bash
defaults write com.knollsoft.Rectangle unsnapRestore -int 2
```

## تغيير الهوامش لمناطق الرصف

يمكن تكوين كل هامش بشكل منفصل، والقيمة الافتراضية هي 5

```bash
defaults write com.knollsoft.Rectangle snapEdgeMarginTop -int 10
defaults write com.knollsoft.Rectangle snapEdgeMarginBottom -int 10
defaults

 write com.knollsoft.Rectangle snapEdgeMarginLeft -int 10
defaults write com.knollsoft.Rectangle snapEdgeMarginRight -int 10
```

## تعيين حواش عند حواف الشاشة

يمكنك تحديد الحواش عند حواف الشاشة التي ستبقى غير مغطاة بعمليات تغيير حجم النوافذ. يُفيد هذا إذا كنت تستخدم بديلًا للمهام يجب أن تكون لديه نوافذ لا يجب أن تتداخل معه.

```bash
defaults write com.knollsoft.Rectangle screenEdgeGapTop -int 10
defaults write com.knollsoft.Rectangle screenEdgeGapBottom -int 10
defaults write com.knollsoft.Rectangle screenEdgeGapLeft -int 10
defaults write com.knollsoft.Rectangle screenEdgeGapRight -int 10
```

إذا كنت ترغب في تطبيق هذه الحواش على الشاشة الرئيسية فقط، يمكنك تعيين screenEdgeGapsOnMainScreenOnly إلى true. مفيد للإعدادات متعددة الشاشات حيث تحتوي شاشة واحدة فقط على بديل للمهام.

```bash
defaults write com.knollsoft.Rectangle screenEdgeGapsOnMainScreenOnly -bool true
```

## تجاهل مناطق السحب المحددة للرصف

يمكن تجاهل كل منطقة سحب للرصف على حافة الشاشة بواسطة أمر واحد في سطر الأوامر، ولكنه يعتبر تعيين حقل بتي لذلك يجب تحديد الحقول المراد تعطيلها.

| بت | منطقة السحب               | إجراء النافذة      |
|-----|---------------------------|---------------------|
| 0   | أعلى                      | تكبير              |
| 1   | أسفل                      | ثلثين              |
| 2   | اليسار                    | نصف اليسار         |
| 3   | اليمين                    | نصف اليمين         |
| 4   | أعلى اليسار               | الزاوية اليسرى العليا  |
| 5   | أعلى اليمين               | الزاوية اليمنى العليا  |
| 6   | أسفل اليسار               | الزاوية اليسرى السفلى  |
| 7   | أسفل اليمين               | الزاوية اليمنى السفلى  |
| 8   | أعلى اليسار أسفل الزاوية  | النصف العلوي         |
| 9   | أعلى اليمين أسفل الزاوية | النصف العلوي         |
| 10  | أسفل اليسار أعلى الزاوية | النصف السفلي         |
| 11  | أسفل اليمين أعلى الزاوية | النصف السفلي         |

لتعطيل منطقة السحب العلوية (التكبير)، قم بتنفيذ الأمر التالي:

```bash
defaults write com.knollsoft.Rectangle ignoredSnapAreas -int 1
```

لتعطيل منطقة النصف العلوي والنصف السفلي، سيكون الحقل بت هو 1111 0000 0000، أو 3840

```bash
defaults write com.knollsoft.Rectangle ignoredSnapAreas -int 3840
```

## تعطيل الحواش عند التكبير

بشكل افتراضي، يُطبق إعداد "الحواش بين النوافذ" على "التكبير" و "تكبير الارتفاع".

لتعطيل الحواش للتكبير، قم بتنفيذ الأمر التالي:

```bash
defaults write com.knollsoft.Rectangle applyGapsToMaximize -int 2
```

لتعطيل الحواش لتكبير الارتفاع، قم بتنفيذ الأمر التالي:

```bash
defaults write com.knollsoft.Rectangle applyGapsToMaximizeHeight -int 2
```

## تمكين مناطق الرصف للأسدس

لتمكين مناطق الرصف للأسدس، قم بتنفيذ:

```bash
defaults write com.knollsoft.Rectangle sixthsSnapArea -bool true
```

بمجرد التمكين، يمكنك سحب النافذة إلى الزاوية، ثم نقلها على طول الحافة نحو منطقة الثلث للرصف للأسدس.

## نقل المؤشر مع النافذة

هناك خيار في واجهة المستخدم لنقل المؤشر مع النافذة عند التنقل عبر الشاشات، ولكن هناك خيار لنقله مع أي اختصار:

```bash
defaults write com.knollsoft.Rectangle moveCursor -int 1
```

## منع النافذة التي يتم سحبها بسرعة فوق شريط القوائم من الانتقال إلى مركز التح

كم

مهم: قد يتسبب ذلك في مشاكل في سحب وإسقاط بعض التطبيقات مثل Adobe Illustrator، وقد يؤثر على اختيار النص في عدد قليل من التطبيقات أيضًا.

ستظل النوافذ التي يتم نقلها ببطء فوق شريط القوائم تذهب إلى مركز التحكم.

بمجرد تمكين هذا، سيكون مربع الاختيار مرئيًا في علامة التبويب Snap Areas في نافذة التفضيلات.

```bash
defaults write com.knollsoft.Rectangle missionControlDragging -int 2
```

تغيير المسافة المسموح بها خارج الشاشة. القيمة بالبكسل وتعتمد على السرعة. القيمة الافتراضية هي 25.

```bash
defaults write com.knollsoft.Rectangle missionControlDraggingAllowedOffscreenDistance -float <المسافة>
```

تغيير مدة الاستبعاد. القيمة بالميلي ثانية. القيمة الافتراضية هي 250.

```bash
defaults write com.knollsoft.Rectangle missionControlDraggingDisallowedDuration -int <المدة>
```

## تغيير سلوك النقر المزدوج على شريط عنوان النافذة

لتغيير الإجراء ([القائمة](https://github.com/rxhanson/Rectangle/blob/master/Rectangle/WindowAction.swift)):

```bash
defaults write com.knollsoft.Rectangle doubleClickTitleBar -int <معرف_الإجراء + 1>
```

لتعطيل الاستعادة عند النقر المزدوج مرة أخرى:

```bash
defaults write com.knollsoft.Rectangle doubleClickTitleBarRestore -int 2
```
