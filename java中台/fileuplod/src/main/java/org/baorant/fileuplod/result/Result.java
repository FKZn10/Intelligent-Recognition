package org.baorant.fileuplod.result;

import lombok.Data;

@Data
public class Result<T> {
   private int code;
   private String msg;
   private T data;

   //成功相应
   public static <T> Result <T> success(Object data){
      Result <T> result = new Result<>();
      result.setCode(200);
      result.setMsg("操作成功");
      result.setData((T) data);
      return result;
   }

   //失败相应
    public static <T> Result<T> fail(String msg){
      Result<T> result = new Result<>();
      result.setCode(500);
      result.setMsg(msg);
      result.setData(null);
      return result;
    }
}
