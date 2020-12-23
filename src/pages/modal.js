import React from 'react';
import styled from "styled-components";
import ReactPlayer from "react-player";


function Modal({location}) {
  console.log(location)
  return (
    <StyledContainer>
      <StyledGrid>
        <StyledCover>
          {/* <Img fluid={content.img} alt={content.title} /> */}
        </StyledCover>
        <StyledInfo>
          <h2 wrapper="StyledInfo">
            aspernatur ab eos, soluta, rerum dolorem, consequuntur voluptate.
            Libero esse excepturi quis illum tempore, facere, voluptas
            laboriosam, placeat atque quo dolorum obcaecati repellat expedita
            eligendi officia distinctio omnis? Praesentium consequatur, eaque
            suscipit totam nemo repudiandae sapiente, perspiciatis fugiat esse
            quibusdam, est nesciunt animi. Provident nam, nihil animi sint rem
            architecto error fugit alias necessitatibus esse consequatur cumque
            maxime ipsum voluptatibus eius qui? Placeat, perspiciatis ipsam
            tempora eum ducimus et quam.
          </h2>
        </StyledInfo>
        <div>
          <ReactPlayer
            wrapper="div"
            url="https://www.youtube.com/watch?v=ysz5S6PUM-U"
          />
        </div>
      </StyledGrid>
    </StyledContainer>
  );
}

export default Modal;


const StyledContainer = styled.div`
  display: flex;
  justify-content: center;
  align-items: center;
  height: 80vh;
`;

const StyledGrid = styled.div`
  display: grid;
  grid-template-columns: 2;
  grid-template-rows: 4;
  gap: 25px;
`;

const StyledInfo = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;

  grid-column: 2;
  grid-row: span 4;
`;
const StyledCover = styled.div`
  box-shadow: 0px 0px 10px 4px #e0e0e0;

  grid-row: span 3;
`;


// import React from "react";
// //import Img from "gatsby-image";
// import styled from "styled-components";
// import ReactPlayer from "react-player";

// function Modal({location}) {

//   return (
//     <StyledContainer>
//       <StyledGrid>
//         <StyledCover>
//           {/* <Img fluid={content.img} alt={content.title} /> */}
//         </StyledCover>
//         <StyledInfo>
//           <h2 wrapper="StyledInfo">
//             aspernatur ab eos, soluta, rerum dolorem, consequuntur voluptate.
//             Libero esse excepturi quis illum tempore, facere, voluptas
//             laboriosam, placeat atque quo dolorum obcaecati repellat expedita
//             eligendi officia distinctio omnis? Praesentium consequatur, eaque
//             suscipit totam nemo repudiandae sapiente, perspiciatis fugiat esse
//             quibusdam, est nesciunt animi. Provident nam, nihil animi sint rem
//             architecto error fugit alias necessitatibus esse consequatur cumque
//             maxime ipsum voluptatibus eius qui? Placeat, perspiciatis ipsam
//             tempora eum ducimus et quam.
//           </h2>
//         </StyledInfo>
//         <div>
//           <ReactPlayer
//             wrapper="StyledMusicVideo"
//             url="https://www.youtube.com/watch?v=ysz5S6PUM-U"
//           />
//         </div>
//       </StyledGrid>
//     </StyledContainer>
//   );
// }
// const StyledContainer = styled.div`
//   display: flex;
//   justify-content: center;
//   align-items: center;
//   height: 80vh;
// `;

// const StyledGrid = styled.div`
//   display: grid;
//   grid-template-columns: 2;
//   grid-template-rows: 4;
//   gap: 25px;
// `;

// const StyledInfo = styled.div`
//   box-shadow: 0px 0px 10px 4px #e0e0e0;

//   grid-column: 2;
//   grid-row: span 4;
// `;
// const StyledCover = styled.div`
//   box-shadow: 0px 0px 10px 4px #e0e0e0;

//   grid-row: span 3;
// `;

// // const StyledMusicVideo = styled.div`
// //   box-shadow: 0px 0px 10px 4px #e0e0e0;
// //   border: 1px solid gold;
// // `;
// // const StyledReturnButton = styled.div`
// //   box-shadow: 0px 0px 10px 4px #e0e0e0;
// //   border: 1px solid gold;
// // `;
// export default Modal;
