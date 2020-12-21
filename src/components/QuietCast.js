import React from "react";
import Img from "gatsby-image";

function QuietCast({data}) {
  console.log(data[0].image.asset.fluid);
  return (
    <div>
      <h1>{data[0].name}</h1>
      <div className="mainImgaeHolder">
        <Img fluid={data[0].image.asset.fluid} alt={data.name} />
      </div>
      <div>
        {data.map((info) => (
          <p>test</p>
        ))}
      </div>
    </div>
  );
}

export default QuietCast;
