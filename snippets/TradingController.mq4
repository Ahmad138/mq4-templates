// Trading controller v7.5

#include <actions/AOrderAction.mq4>
#include <enums/OrderSide.mq4>

class TradingController
{
   ENUM_TIMEFRAMES _entryTimeframe;
   ENUM_TIMEFRAMES _exitTimeframe;
   datetime _lastActionTime;
   double _lastLot;
   ActionOnConditionLogic* actions;
   Signaler *_signaler;
   datetime _lastLimitPositionMessage;
   datetime _lastEntryTime;
   datetime _lastExitTime;
   TradingCalculator *_calculator;
   ICondition* _longCondition;
   ICondition* _shortCondition;
   ICondition* _longFilterCondition;
   ICondition* _shortFilterCondition;
   ICondition* _exitLongCondition;
   ICondition* _exitShortCondition;
   #ifdef MARTINGALE_FEATURE
   IMartingaleStrategy *_shortMartingale;
   IMartingaleStrategy *_longMartingale;
   #endif
   IMoneyManagementStrategy *_longMoneyManagement[];
   IMoneyManagementStrategy *_shortMoneyManagement[];
   ICloseOnOppositeStrategy *_closeOnOpposite;
   #ifdef POSITION_CAP_FEATURE
   IPositionCapStrategy *_longPositionCap;
   IPositionCapStrategy *_shortPositionCap;
   #endif
   IEntryStrategy *_entryStrategy;
   string _algorithmId;
   ActionOnConditionLogic* _actions;
   AOrderAction* _orderHandlers[];
   TradingMode _entryLogic;
   TradingMode _exitLogic;
   bool _ecnBroker;
   int _logFile;
public:
   TradingController(TradingCalculator *calculator, 
                     ENUM_TIMEFRAMES entryTimeframe, 
                     ENUM_TIMEFRAMES exitTimeframe, 
                     Signaler *signaler, 
                     const string algorithmId = "")
   {
      _lastLimitPositionMessage = 0;
      _ecnBroker = false;
      _entryLogic = TradingModeOnBarClose;
      _exitLogic = TradingModeLive;
      _actions = NULL;
      _algorithmId = algorithmId;
      #ifdef POSITION_CAP_FEATURE
      _longPositionCap = NULL;
      _shortPositionCap = NULL;
      #endif
      _closeOnOpposite = NULL;
      #ifdef MARTINGALE_FEATURE
      _shortMartingale = NULL;
      _longMartingale = NULL;
      #endif
      _longCondition = NULL;
      _shortCondition = NULL;
      _longFilterCondition = NULL;
      _shortFilterCondition = NULL;
      _calculator = calculator;
      _signaler = signaler;
      _entryTimeframe = entryTimeframe;
      _exitTimeframe = exitTimeframe;
      _lastLot = lots_value;
      _exitLongCondition = NULL;
      _exitShortCondition = NULL;
      _logFile = -1;
   }

   ~TradingController()
   {
      if (_logFile != -1)
      {
         FileClose(_logFile);
      }
      for (int i = 0; i < ArraySize(_orderHandlers); ++i)
      {
         delete _orderHandlers[i];
      }
      delete _actions;
      delete _entryStrategy;
      #ifdef POSITION_CAP_FEATURE
      delete _longPositionCap;
      delete _shortPositionCap;
      #endif
      delete _closeOnOpposite;
      for (int i = 0; i < ArraySize(_longMoneyManagement); ++i)
      {
         delete _longMoneyManagement[i];
      }
      for (int i = 0; i < ArraySize(_shortMoneyManagement); ++i)
      {
         delete _shortMoneyManagement[i];
      }
      #ifdef MARTINGALE_FEATURE
      delete _shortMartingale;
      delete _longMartingale;
      #endif
      if (_exitLongCondition != NULL)
         _exitLongCondition.Release();
      if (_exitShortCondition != NULL)
         _exitShortCondition.Release();
      delete _calculator;
      delete _signaler;
      if (_longCondition != NULL)
         _longCondition.Release();
      if (_shortCondition != NULL)
         _shortCondition.Release();
      if (_longFilterCondition != NULL)
         _longFilterCondition.Release();
      if (_shortFilterCondition != NULL)
         _shortFilterCondition.Release();
   }

   void AddOrderAction(AOrderAction* orderAction)
   {
      int count = ArraySize(_orderHandlers);
      ArrayResize(_orderHandlers, count + 1);
      _orderHandlers[count] = orderAction;
      orderAction.AddRef();
   }
   void SetECNBroker(bool ecn) { _ecnBroker = ecn; }
   void SetPrintLog(string logFile)
   {
      _logFile = FileOpen(logFile, FILE_WRITE | FILE_CSV, ",");
   }
   void SetEntryLogic(TradingMode logicType) { _entryLogic = logicType; }
   void SetExitLogic(TradingMode logicType) { _exitLogic = logicType; }
   void SetActions(ActionOnConditionLogic* __actions) { _actions = __actions; }
   void SetLongCondition(ICondition *condition) { _longCondition = condition; }
   void SetShortCondition(ICondition *condition) { _shortCondition = condition; }
   void SetLongFilterCondition(ICondition *condition) { _longFilterCondition = condition; }
   void SetShortFilterCondition(ICondition *condition) { _shortFilterCondition = condition; }
   void SetExitLongCondition(ICondition *condition) { _exitLongCondition = condition; }
   void SetExitShortCondition(ICondition *condition) { _exitShortCondition = condition; }
   #ifdef MARTINGALE_FEATURE
   void SetShortMartingaleStrategy(IMartingaleStrategy *martingale) { _shortMartingale = martingale; }
   void SetLongMartingaleStrategy(IMartingaleStrategy *martingale) { _longMartingale = martingale; }
   #endif
   void AddLongMoneyManagement(IMoneyManagementStrategy *moneyManagement)
   {
      int count = ArraySize(_longMoneyManagement);
      ArrayResize(_longMoneyManagement, count + 1);
      _longMoneyManagement[count] = moneyManagement;
   }
   void AddShortMoneyManagement(IMoneyManagementStrategy *moneyManagement)
   {
      int count = ArraySize(_shortMoneyManagement);
      ArrayResize(_shortMoneyManagement, count + 1);
      _shortMoneyManagement[count] = moneyManagement;
   }
   void SetCloseOnOpposite(ICloseOnOppositeStrategy *closeOnOpposite) { _closeOnOpposite = closeOnOpposite; }
   #ifdef POSITION_CAP_FEATURE
      void SetLongPositionCap(IPositionCapStrategy *positionCap) { _longPositionCap = positionCap; }
      void SetShortPositionCap(IPositionCapStrategy *positionCap) { _shortPositionCap = positionCap; }
   #endif
   void SetEntryStrategy(IEntryStrategy *entryStrategy) { _entryStrategy = entryStrategy; }

   void DoTrading()
   {
      int entryTradePeriod = _entryLogic == TradingModeLive ? 0 : 1;
      datetime entryTime = iTime(_calculator.GetSymbol(), _entryTimeframe, entryTradePeriod);
      _actions.DoLogic(entryTradePeriod, entryTime);
      #ifdef MARTINGALE_FEATURE
         DoMartingale(_shortMartingale);
         DoMartingale(_longMartingale);
      #endif
      if (EntryAllowed(entryTime))
      {
         if (DoEntryLogic(entryTradePeriod, entryTime))
            _lastActionTime = entryTime;
         _lastEntryTime = entryTime;
      }

      int exitTradePeriod = _exitLogic == TradingModeLive ? 0 : 1;
      datetime exitTime = iTime(_calculator.GetSymbol(), _exitTimeframe, exitTradePeriod);
      if (ExitAllowed(exitTime))
      {
         DoExitLogic(exitTradePeriod, exitTime);
         _lastExitTime = exitTime;
      }
   }
private:
   bool ExitAllowed(datetime exitTime)
   {
      return _exitLogic != TradingModeOnBarClose || _lastExitTime != exitTime;
   }

   void DoExitLogic(int exitTradePeriod, datetime date)
   {
      if (_logFileHandle != -1)
      {
         string exitLongLogMessage = _exitLongCondition.GetLogMessage(exitTradePeriod, date);
         string exitShortLogMessage = _exitShortCondition.GetLogMessage(exitTradePeriod, date);
         FileWrite(_logFileHandle, TimeToString(TimeCurrent()), "Exit long: " + exitLongLogMessage, "Exit short: " + exitShortLogMessage);
      }
      if (_exitLongCondition.IsPass(exitTradePeriod, date))
      {
         if (_entryStrategy.Exit(BuySide) > 0)
            _signaler.SendNotifications("Exit Buy");
      }
      if (_exitShortCondition.IsPass(exitTradePeriod, date))
      {
         if (_entryStrategy.Exit(SellSide) > 0)
            _signaler.SendNotifications("Exit Sell");
      }
   }

   bool EntryAllowed(datetime entryTime)
   {
      if (_entryLogic == TradingModeOnBarClose)
         return _lastEntryTime != entryTime;
      return _lastActionTime != entryTime;
   }

   bool DoEntryLongLogic(int period, datetime date, string& logMessage)
   {
      if (_logFile != -1)
      {
         logMessage = _longCondition.GetLogMessage(period, date);
      }
      if (!_longCondition.IsPass(period, date))
      {
         return false;
      }
      if (_longFilterCondition != NULL && !_longFilterCondition.IsPass(period, date))
      {
         return false;
      }
      _closeOnOpposite.DoClose(SellSide);
      #ifdef POSITION_CAP_FEATURE
         if (_longPositionCap.IsLimitHit())
         {
            if (_lastLimitPositionMessage != date)
            {
               _signaler.SendNotifications("Positions limit has been reached");
            }
            _lastLimitPositionMessage = date;
            return false;
         }
      #endif
      for (int i = 0; i < ArraySize(_longMoneyManagement); ++i)
      {
         int order = _entryStrategy.OpenPosition(period, BuySide, _longMoneyManagement[i], _algorithmId, _ecnBroker);
         if (order >= 0)
         {
            for (int orderHandlerIndex = 0; orderHandlerIndex < ArraySize(_orderHandlers); ++orderHandlerIndex)
            {
               _orderHandlers[orderHandlerIndex].DoAction(order);
            }
            #ifdef MARTINGALE_FEATURE
               _longMartingale.OnOrder(order);
            #endif
         }
      }
      _signaler.SendNotifications("Buy");
      return true;
   }

   bool DoEntryShortLogic(int period, datetime date, string& logMessage)
   {
      if (_logFileHandle)
      {
         logMessage = _shortCondition.GetLogMessage(period, date);
      }
      if (!_shortCondition.IsPass(period, date))
      {
         return false;
      }
      if (_shortFilterCondition != NULL && !_shortFilterCondition.IsPass(period, date))
      {
         return false;
      }
      _closeOnOpposite.DoClose(BuySide);
      #ifdef POSITION_CAP_FEATURE
         if (_shortPositionCap.IsLimitHit())
         {
            if (_lastLimitPositionMessage != date)
            {
               _signaler.SendNotifications("Positions limit has been reached");
            }
            _lastLimitPositionMessage = date;
            return false;
         }
      #endif
      for (int i = 0; i < ArraySize(_shortMoneyManagement); ++i)
      {
         int order = _entryStrategy.OpenPosition(period, SellSide, _shortMoneyManagement[i], _algorithmId, _ecnBroker);
         if (order >= 0)
         {
            for (int orderHandlerIndex = 0; orderHandlerIndex < ArraySize(_orderHandlers); ++orderHandlerIndex)
            {
               _orderHandlers[orderHandlerIndex].DoAction(order);
            }
            #ifdef MARTINGALE_FEATURE
               _shortMartingale.OnOrder(order);
            #endif
         }
      }
      _signaler.SendNotifications("Sell");
      return true;
   }

   bool DoEntryLogic(int entryTradePeriod, datetime date)
   {
      string entryLongLogMessage;
      string entryShortLogMessage;
      bool longOpened = DoEntryLongLogic(entryTradePeriod, date, entryLongLogMessage);
      bool shortOpened = DoEntryShortLogic(entryTradePeriod, date, entryShortLogMessage);
      if (_logFile != -1)
      {
         FileWrite(_logFileHandle, TimeToString(TimeCurrent()), "Entry long: " + entryLongLogMessage, "Entry short: " + entryShortLogMessage);
      }
      return longOpened || shortOpened;
   }

   #ifdef MARTINGALE_FEATURE
   void DoMartingale(IMartingaleStrategy *martingale)
   {
      OrderSide anotherSide;
      if (martingale.NeedAnotherPosition(anotherSide))
      {
         double initialLots = OrderLots();
         IMoneyManagementStrategy* moneyManagement = martingale.GetMoneyManagement();
         int order = _entryStrategy.OpenPosition(0, anotherSide, moneyManagement, "Martingale position", _ecnBroker);
         if (order >= 0)
         {
            // if (_printLog)
            // {
            //    double newLots = 0;
            //    if (OrderSelect(order, SELECT_BY_TICKET, MODE_TRADES))
            //    {
            //       newLots = OrderLots();
            //    }
            //    Print("Opening martingale position. Initial lots: " + DoubleToString(initialLots) 
            //       + ". New martingale lots: " + DoubleToString(newLots));
            // }
            martingale.OnOrder(order);
         }
         if (anotherSide == BuySide)
            _signaler.SendNotifications("Opening martingale long position");
         else
            _signaler.SendNotifications("Opening martingale short position");
      }
   }
   #endif
};